require "test_helper"

class CrossReferenceLookupTest < ActiveSupport::TestCase
  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    @rom = Book.create!(osis_code: "Rom", name: "Romans", testament: :new, position: 45, chapter_count: 16)
    @john1 = Book.create!(osis_code: "1John", name: "1 John", testament: :new, position: 62, chapter_count: 5)

    CrossReference.create!(from_book: @john, from_chapter: 3, from_verse: 16,
                           to_book: @rom, to_chapter_start: 5, to_verse_start: 8, votes: 84)
    CrossReference.create!(from_book: @john, from_chapter: 3, from_verse: 16,
                           to_book: @john1, to_chapter_start: 4, to_verse_start: 9, to_verse_end: 10, votes: 76)

    Verse.create!(translation: @kjv, book: @rom, chapter: 5, verse_number: 8, text: "But God commendeth his love...")
    Verse.create!(translation: @kjv, book: @john1, chapter: 4, verse_number: 9, text: "In this was manifested the love of God...")
  end

  test "returns rows ordered by votes with previews from the chosen translation" do
    rows = CrossReferenceLookup.for_verse(book: @john, chapter: 3, verse: 16, translation: @kjv)
    assert_equal [ "Romans 5:8", "1 John 4:9-10" ], rows.map(&:reference)
    assert_equal [ 84, 76 ], rows.map(&:votes)
    assert_equal "But God commendeth his love...", rows.first.preview
    assert_equal "In this was manifested the love of God...", rows.second.preview
  end

  test "preview is nil when the target verse is absent in the translation" do
    asv = Translation.create!(code: "ASV", name: "American Standard Version")
    rows = CrossReferenceLookup.for_verse(book: @john, chapter: 3, verse: 16, translation: asv)
    assert_nil rows.first.preview
  end
end
