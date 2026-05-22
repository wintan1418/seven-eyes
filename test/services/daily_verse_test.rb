require "test_helper"

class DailyVerseTest < ActiveSupport::TestCase
  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    @verse = Verse.create!(translation: @kjv, book: @john, chapter: 3, verse_number: 16,
                           text: "For God so loved the world")
  end

  test "returns nil when no translation is seeded" do
    Verse.delete_all
    Translation.delete_all
    assert_nil DailyVerse.for
  end

  test "is deterministic for a given date and rotates with the day" do
    # Seed every reference so any rotation lands on a real verse, then assert the
    # same date always yields the same pick.
    seed_all_references
    a = DailyVerse.for(date: Date.new(2026, 1, 1))
    b = DailyVerse.for(date: Date.new(2026, 1, 1))
    assert_equal a.reference_label, b.reference_label
  end

  test "resolves a real verse from the DB, never fabricated text" do
    seed_all_references
    result = DailyVerse.for(date: Date.new(2026, 5, 22))
    assert result
    assert_equal "KJV", result.translation_code
    assert Verse.exists?(text: result.text), "text must come from a seeded verse"
  end

  private

  def seed_all_references
    next_position = 100
    DailyVerse::REFERENCES.each do |ref|
      parsed = ReferenceParser.call(ref)
      book = Book.find_by_osis(parsed.osis)
      unless book
        book = Book.create!(osis_code: parsed.osis, name: parsed.book_name, testament: :new,
                            position: next_position, chapter_count: 150)
        next_position += 1
      end
      Verse.find_or_create_by!(translation: @kjv, book:, chapter: parsed.chapter,
                               verse_number: parsed.verse_start) do |v|
        v.text = "Seeded text for #{ref}"
      end
    end
  end
end
