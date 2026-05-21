require "test_helper"

class StudyWorkflowTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @bsb = Translation.create!(code: "BSB", name: "Berean Standard Bible")
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    Verse.create!(translation: @kjv, book: @john, chapter: 3, verse_number: 16,
                  text: "For God so loved the world, that he gave his only begotten Son")
    Verse.create!(translation: @bsb, book: @john, chapter: 3, verse_number: 16,
                  text: "For God so loved the world that He gave His one and only Son")
  end

  test "creating a study makes panes and renders the workspace" do
    assert_difference -> { users(:one).studies.count }, 1 do
      post studies_path
    end
    study = Study.last
    follow_redirect!
    assert_response :success
    assert_select ".ps-workspace.cols-4"
    assert_select "turbo-frame.ps-pane", count: 4
  end

  test "updating a pane reference loads the verse into its frame" do
    study = users(:one).studies.create!(name: "S", pane_count: 1)
    pane = study.panes.first

    patch study_pane_path(study, pane), params: { pane: { reference: "Jn 3:16", translation_id: @kjv.id } }
    assert_response :success
    assert_select "turbo-frame##{pane.frame_id}"
    assert_includes response.body, "only begotten Son"
    assert_equal "Jn 3:16", pane.reload.reference
  end

  test "switching translation re-renders the same verse in the new version" do
    study = users(:one).studies.create!(name: "S", pane_count: 1)
    pane = study.panes.first
    pane.update!(reference: "John 3:16", translation: @kjv)

    patch study_pane_path(study, pane), params: { pane: { reference: "John 3:16", translation_id: @bsb.id } }
    assert_includes response.body, "one and only Son"
    assert_equal @bsb, pane.reload.translation
  end
end
