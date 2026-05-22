require "test_helper"

class CommentaryEndpointTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    Commentary.create!(source: "matthew-henry", source_name: "Matthew Henry", book: @john, chapter: 3,
                       body: %(<span class="cm-vref">v. 1</span><p>We found, in the close...</p>))
    @study = users(:one).studies.create!(name: "S", pane_count: 2)
  end

  test "commentary renders the drawer frame with the chapter exposition" do
    get commentary_study_path(@study, osis: "John", chapter: 3)
    assert_response :success
    assert_select "turbo-frame#commentary_drawer"
    assert_includes response.body, "Matthew Henry"
    assert_includes response.body, "We found, in the close"
  end

  test "unknown book returns 404" do
    get commentary_study_path(@study, osis: "Nope", chapter: 1)
    assert_response :not_found
  end

  test "chapter with no commentary shows an empty-state message" do
    get commentary_study_path(@study, osis: "John", chapter: 99)
    assert_response :success
    assert_includes response.body, "No commentary"
  end
end
