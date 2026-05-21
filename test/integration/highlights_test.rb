require "test_helper"

class HighlightsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    @verse = Verse.create!(translation: @kjv, book: @john, chapter: 3, verse_number: 16, text: "For God so loved the world")
  end

  test "create persists a highlight for the current user and returns json" do
    assert_difference -> { users(:one).highlights.count }, 1 do
      post highlights_path, params: { highlight: { verse_id: @verse.id, color: "ochre", char_start: 8, char_end: 27 } }, as: :json
    end
    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "ochre", body["color"]
  end

  test "invalid range is rejected" do
    post highlights_path, params: { highlight: { verse_id: @verse.id, color: "sage", char_start: 5, char_end: 5 } }, as: :json
    assert_response :unprocessable_entity
  end

  test "destroy removes only the owner's highlight" do
    h = users(:one).highlights.create!(verse: @verse, color: :rose, char_start: 0, char_end: 3)
    assert_difference -> { Highlight.count }, -1 do
      delete highlight_path(h)
    end
    assert_response :no_content
  end

  test "cannot destroy another user's highlight" do
    other = users(:two).highlights.create!(verse: @verse, color: :cobalt, char_start: 0, char_end: 3)
    delete highlight_path(other)
    assert_response :not_found
    assert Highlight.exists?(other.id)
  end
end
