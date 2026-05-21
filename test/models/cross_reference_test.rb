require "test_helper"

class CrossReferenceTest < ActiveSupport::TestCase
  setup do
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    @rom = Book.create!(osis_code: "Rom", name: "Romans", testament: :new, position: 45, chapter_count: 16)
    CrossReference.create!(from_book: @john, from_chapter: 3, from_verse: 16,
                           to_book: @rom, to_chapter_start: 5, to_verse_start: 8, votes: 84)
    CrossReference.create!(from_book: @john, from_chapter: 3, from_verse: 16,
                           to_book: @rom, to_chapter_start: 8, to_verse_start: 32, votes: 71)
    CrossReference.create!(from_book: @john, from_chapter: 3, from_verse: 17,
                           to_book: @rom, to_chapter_start: 1, to_verse_start: 1, votes: 10)
  end

  test "for_verse returns only that verse's refs, best votes first" do
    refs = CrossReference.for_verse(book_id: @john.id, chapter: 3, verse: 16)
    assert_equal [ 84, 71 ], refs.map(&:votes)
  end

  test "to_label renders single, range, and cross-chapter forms" do
    single = CrossReference.new(to_book: @rom, to_chapter_start: 5, to_verse_start: 8)
    assert_equal "Romans 5:8", single.to_label

    range = CrossReference.new(to_book: @rom, to_chapter_start: 8, to_verse_start: 28, to_verse_end: 30)
    assert_equal "Romans 8:28-30", range.to_label

    cross = CrossReference.new(to_book: @rom, to_chapter_start: 8, to_verse_start: 38,
                               to_chapter_end: 9, to_verse_end: 1)
    assert_equal "Romans 8:38-9:1", cross.to_label
  end
end
