require "test_helper"

class VerseSearchTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @matt = Book.create!(osis_code: "Matt", name: "Matthew", testament: :new, position: 40, chapter_count: 28)
    Verse.create!(translation: @kjv, book: @matt, chapter: 5, verse_number: 44,
                  text: "But I say unto you, Love your enemies, bless them that curse you")
    @study = users(:one).studies.create!(name: "S", pane_count: 2)
  end

  test "search renders the results frame with matches and per-pane load buttons" do
    get search_study_path(@study, q: "love your enemies", translation_id: @kjv.id)
    assert_response :success
    assert_select "turbo-frame#verse_search_results"
    assert_includes response.body, "Matthew 5:44"
    assert_select "form[data-turbo-frame=?]", @study.panes.first.frame_id
  end

  test "blank query renders a hint, no results" do
    get search_study_path(@study, q: "")
    assert_response :success
    refute_includes response.body, "Matthew 5:44"
  end

  test "no matches renders a friendly message" do
    get search_study_path(@study, q: "zzqxqwx", translation_id: @kjv.id)
    assert_response :success
    assert_includes response.body, "No matches"
  end
end
