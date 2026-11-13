require "test_helper"

class KeyPassagesTest < ActiveSupport::TestCase
  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    eph = Book.create!(osis_code: "Eph", name: "Ephesians", testament: :new, position: 49, chapter_count: 6)
    Verse.create!(translation: @kjv, book: eph, chapter: 2, verse_number: 8, text: "For by grace are ye saved")
    Verse.create!(translation: @kjv, book: eph, chapter: 2, verse_number: 9, text: "Not of works")
  end

  test "resolves references to our own text, with a reader slug" do
    passages = KeyPassages.call([ "Ephesians 2:8-9", "Eph 2:8" ])
    assert_equal [ "Ephesians 2:8-9", "Ephesians 2:8" ], passages.map(&:label)
    assert_equal "For by grace are ye saved Not of works", passages.first.text
    assert_equal "ephesians-2-8-9", passages.first.slug
    assert_equal "KJV", passages.first.translation_code
  end

  test "drops references that don't parse or aren't seeded" do
    assert_empty KeyPassages.call([ "Nonsense 1:1", "John 3:16", "Ephesians 2" ])
  end

  test "no translation, no passages" do
    assert_empty KeyPassages.call([ "Ephesians 2:8" ], translation: nil)
  end
end
