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

  test "a Strong's-tagged KJV verse renders clickable word-study links" do
    Verse.find_by(translation: @kjv, book: @john, chapter: 3, verse_number: 16)
         .update!(tokens: [ { "w" => "For", "s" => "G1063" }, { "w" => " God", "s" => "G2316" } ])
    study = users(:one).studies.create!(name: "S", pane_count: 1)
    pane = study.panes.first

    patch study_pane_path(study, pane), params: { pane: { reference: "Jn 3:16", translation_id: @kjv.id } }
    assert_response :success
    assert_select "span.ps-word", minimum: 2
    assert_includes response.body, lexicon_study_path(study, strongs: "G2316")
  end

  test "switching translation re-renders the same verse in the new version" do
    study = users(:one).studies.create!(name: "S", pane_count: 1)
    pane = study.panes.first
    pane.update!(reference: "John 3:16", translation: @kjv)

    patch study_pane_path(study, pane), params: { pane: { reference: "John 3:16", translation_id: @bsb.id } }
    assert_includes response.body, "one and only Son"
    assert_equal @bsb, pane.reload.translation
  end

  # The pane must explain a miss instead of showing "not found": a misspelled
  # book still loads, a chapter past the end names the book's length, and a
  # verse past the end names the chapter's length.
  test "a misspelled book name still loads its chapter" do
    study = users(:one).studies.create!(name: "Test", pane_count: 1)
    pane = study.panes.first
    patch study_pane_path(study, pane), params: { pane: { reference: "jhon 3:16", translation_id: @kjv.id } }
    assert_response :success
    assert_select ".ps-verse", count: 1
    assert_select ".ref-title", /John III/
  end

  test "a bare book name loads chapter 1" do
    Verse.create!(translation: @kjv, book: @john, chapter: 1, verse_number: 1, text: "In the beginning was the Word")
    study = users(:one).studies.create!(name: "Test", pane_count: 1)
    pane = study.panes.first
    patch study_pane_path(study, pane), params: { pane: { reference: "John", translation_id: @kjv.id } }
    assert_response :success
    assert_select ".ref-title", /John I\b/
  end

  test "a chapter past the end of the book says how many chapters it has" do
    study = users(:one).studies.create!(name: "Test", pane_count: 1)
    pane = study.panes.first
    patch study_pane_path(study, pane), params: { pane: { reference: "John 99", translation_id: @kjv.id } }
    assert_response :success
    assert_select ".ps-pane-empty .lead", /John has 21 chapters/
  end

  test "a verse past the end of the chapter says how many verses it has" do
    study = users(:one).studies.create!(name: "Test", pane_count: 1)
    pane = study.panes.first
    patch study_pane_path(study, pane), params: { pane: { reference: "John 3:40", translation_id: @kjv.id } }
    assert_response :success
    assert_select ".ps-pane-empty .lead", /John 3 has 16 verses/
  end

  test "an unknown book is named back to the reader" do
    study = users(:one).studies.create!(name: "Test", pane_count: 1)
    pane = study.panes.first
    patch study_pane_path(study, pane), params: { pane: { reference: "Xylophone 4", translation_id: @kjv.id } }
    assert_response :success
    assert_select ".ps-pane-empty .lead", /No book called .Xylophone./
  end
end
