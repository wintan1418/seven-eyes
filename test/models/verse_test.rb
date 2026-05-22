require "test_helper"

class VerseTest < ActiveSupport::TestCase
  setup do
    @t = Translation.create!(code: "TST", name: "Test")
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    (14..17).each do |n|
      Verse.create!(translation: @t, book: @john, chapter: 3, verse_number: n, text: "verse #{n}")
    end
  end

  test "passage loads a contiguous verse range in order" do
    rows = Verse.passage(translation: @t, book: @john, chapter: 3, verse_start: 15, verse_end: 17)
    assert_equal [ 15, 16, 17 ], rows.map(&:verse_number)
  end

  test "passage with a single verse" do
    rows = Verse.passage(translation: @t, book: @john, chapter: 3, verse_start: 16)
    assert_equal [ 16 ], rows.map(&:verse_number)
  end

  test "passage without verse bounds returns the whole chapter ordered" do
    rows = Verse.passage(translation: @t, book: @john, chapter: 3)
    assert_equal [ 14, 15, 16, 17 ], rows.map(&:verse_number)
  end

  test "verse_number is unique within translation+book+chapter" do
    dup = Verse.new(translation: @t, book: @john, chapter: 3, verse_number: 16, text: "x")
    refute dup.valid?
  end

  test "search finds verses by word, ranked, scoped to the translation" do
    Verse.create!(translation: @t, book: @john, chapter: 3, verse_number: 18,
                  text: "For God so loved the world that he gave his only Son")
    other = Translation.create!(code: "OTH", name: "Other")
    Verse.create!(translation: other, book: @john, chapter: 3, verse_number: 16,
                  text: "loved the world")

    hits = Verse.search("loved world", translation: @t)
    assert_includes hits.map(&:verse_number), 18
    assert hits.all? { |v| v.translation_id == @t.id }, "must not leak other translations"
  end

  test "search returns nothing for blank or unmatched queries" do
    assert_equal 0, Verse.search("", translation: @t).size
    assert_equal 0, Verse.search("   ", translation: @t).size
    assert_equal 0, Verse.search("zzqxqwx", translation: @t).size
  end
end
