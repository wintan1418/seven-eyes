require "test_helper"

class VerseCountTest < ActionDispatch::IntegrationTest
  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    (1..3).each { |n| Verse.create!(translation: @kjv, book: @john, chapter: 3, verse_number: n, text: "v#{n}") }
  end

  test "returns the highest verse number for a chapter (guests allowed)" do
    get verse_count_path(osis: "John", chapter: 3, translation: "KJV")
    assert_response :success
    assert_equal 3, JSON.parse(response.body)["count"]
  end

  test "unknown book returns zero" do
    get verse_count_path(osis: "Nope", chapter: 1)
    assert_equal 0, JSON.parse(response.body)["count"]
  end
end
