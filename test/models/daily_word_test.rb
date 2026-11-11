require "test_helper"

class DailyWordTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # Composer seam: a stand-in for DailyWordComposer that never touches the network.
  FakeComposer = Struct.new(:result, :calls) do
    def call(_word)
      self.calls = calls.to_i + 1
      result
    end
  end

  def ok_result(reflection: "God loves the world.", prayer: "Lord, teach us. Amen.")
    DailyWordComposer::Result.new(ok: true, reflection:, prayer:)
  end

  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    seed_references(DailyWord::REFERENCES.first(5))
    @date = Date.new(2026, 11, 11)
  end

  test "picks a real passage from the DB, never fabricated text" do
    word = DailyWord.ensure_for(@date)
    assert word.persisted?
    assert_equal @date, word.date
    assert_equal "KJV", word.translation_code
    assert Verse.exists?(text: word.verse_text), "text must be our seeded verse"
  end

  test "the same date always yields the same passage" do
    a = DailyWord.pick(@date)
    b = DailyWord.pick(@date)
    assert_equal a[:reference], b[:reference]
  end

  test "consecutive days walk the list instead of repeating" do
    refs = (0...5).map { |i| DailyWord.ensure_for(@date + i).reference }
    assert_equal 5, refs.uniq.size
  end

  test "skips a passage used within the repeat window" do
    natural = DailyWord.pick(@date)
    DailyWord.create!(DailyWord.pick(@date).merge(date: @date - 10))
    assert_not_equal natural[:reference], DailyWord.pick(@date)[:reference]
  end

  test "a range snapshots every verse and labels the span" do
    seed_references([ "Psalm 23:1-3" ])
    attrs = DailyWord.send(:resolve, "Psalm 23:1-3", @kjv)
    assert_equal "Psalms 23:1-3", attrs[:reference]
    assert_equal [ 1, 3 ], [ attrs[:verse_start], attrs[:verse_end] ]
    assert_includes attrs[:verse_text], "Seeded text for Psalm 23:1-3 v3"
  end

  test "ensure_for creates one row per date" do
    assert_difference -> { DailyWord.count }, 1 do
      2.times { DailyWord.ensure_for(@date) }
    end
  end

  test "two requests racing to create the day's word end up with the same row" do
    winner = DailyWord.ensure_for(@date)
    # The loser looked before the winner committed, so it goes straight to INSERT:
    # the unique index rejects it and create_or_find_by returns the winner's row.
    loser = DailyWord.create_or_find_by!(date: @date) { |w| w.assign_attributes(DailyWord.pick(@date + 1)) }
    assert_equal winner.id, loser.id
    assert_equal winner.reference, loser.reload.reference
    assert_equal 1, DailyWord.where(date: @date).count
  end

  test "returns nil when no Bible is seeded" do
    Verse.delete_all
    Translation.delete_all
    assert_nil DailyWord.ensure_for(@date)
    assert_nil DailyWord.today
  end

  test "only one claim wins, and a failed attempt is retried only after a pause" do
    word = DailyWord.ensure_for(@date)
    assert word.claim_composition
    refute word.claim_composition, "a second request must not compose again"

    travel DailyWord::RETRY_AFTER + 1.minute do
      assert word.claim_composition, "retry once the window has passed"
    end
  end

  test "a composed word is never claimed again (unless forced)" do
    word = DailyWord.ensure_for(@date)
    word.update!(reflection: "Done", prayer: "Amen.", ai_attempted_at: 2.hours.ago)
    refute word.claim_composition
    assert word.claim_composition(force: true)
  end

  test "today creates lazily and enqueues composition exactly once" do
    assert_enqueued_jobs 1, only: DailyWordJob do
      3.times { DailyWord.today }
    end
    assert_equal 1, DailyWord.count
    assert_equal DailyWord.today_date, DailyWord.first.date
  end

  test "today's date follows Lagos, not UTC" do
    travel_to Time.utc(2026, 11, 11, 23, 30) do
      assert_equal Date.new(2026, 11, 12), DailyWord.today_date
    end
  end

  test "compose! stores the reflection and prayer" do
    word = DailyWord.ensure_for(@date)
    assert word.compose!(composer: FakeComposer.new(ok_result))
    word.reload
    assert word.composed?
    assert_equal "God loves the world.", word.reflection
    assert_equal "Lord, teach us. Amen.", word.prayer
    assert word.composed_at
  end

  test "when the AI fails the word keeps the verse alone" do
    word = DailyWord.ensure_for(@date)
    refute word.compose!(composer: FakeComposer.new(DailyWordComposer::Result.new(ok: false, error: :no_key)))
    word.reload
    refute word.composed?
    assert word.verse_text.present?
  end

  test "a failed regeneration keeps the old text" do
    word = DailyWord.ensure_for(@date)
    word.update!(reflection: "Old", prayer: "Old prayer. Amen.")
    refute word.compose!(composer: FakeComposer.new(DailyWordComposer::Result.new(ok: false, error: :api)))
    assert_equal "Old", word.reload.reflection
  end

  test "published excludes future dates" do
    today = DailyWord.today_date
    DailyWord.ensure_for(today)
    DailyWord.ensure_for(today + 1)
    assert_equal [ today ], DailyWord.published.pluck(:date)
  end

  test "share text carries the verse, reference, reflection, prayer and link" do
    word = DailyWord.ensure_for(@date)
    word.update!(reflection: "Reflect.", prayer: "Pray. Amen.")
    text = word.share_text("https://bibliorata.com/today/2026-11-11")
    assert_includes text, word.verse_text
    assert_includes text, "#{word.reference} (KJV)"
    assert_includes text, "Reflect."
    assert_includes text, "Prayer: Pray. Amen."
    assert text.end_with?("https://bibliorata.com/today/2026-11-11")
  end

  test "every curated reference parses" do
    DailyWord::REFERENCES.each do |ref|
      parsed = ReferenceParser.call(ref)
      assert parsed.valid? && parsed.verse_start, "#{ref} should parse to a verse"
    end
  end

  private

  def seed_references(refs)
    refs.each do |ref|
      parsed = ReferenceParser.call(ref)
      book = Book.find_by_osis(parsed.osis) ||
             Book.create!(osis_code: parsed.osis, name: parsed.book_name, testament: :new,
                          position: Book.unscoped.maximum(:position).to_i + 1, chapter_count: 150)
      (parsed.verse_start..(parsed.verse_end || parsed.verse_start)).each do |n|
        Verse.find_or_create_by!(translation: @kjv, book:, chapter: parsed.chapter, verse_number: n) do |v|
          v.text = "Seeded text for #{ref} v#{n}"
        end
      end
    end
  end
end
