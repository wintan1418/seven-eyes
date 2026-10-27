require "test_helper"

class CrossReferencesAndNotesTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    @rom = Book.create!(osis_code: "Rom", name: "Romans", testament: :new, position: 45, chapter_count: 16)
    Verse.create!(translation: @kjv, book: @rom, chapter: 5, verse_number: 8, text: "But God commendeth his love toward us")
    CrossReference.create!(from_book: @john, from_chapter: 3, from_verse: 16,
                           to_book: @rom, to_chapter_start: 5, to_verse_start: 8, votes: 84)
    @study = users(:one).studies.create!(name: "S", pane_count: 2)
  end

  test "cross_references renders the drawer frame with refs and per-pane load buttons" do
    get cross_references_study_path(@study, osis: "John", chapter: 3, verse: 16, translation: "KJV")
    assert_response :success
    assert_select "turbo-frame#xref_drawer"
    assert_includes response.body, "Romans 5:8"
    assert_includes response.body, "But God commendeth his love toward us"
    assert_select "form[data-turbo-frame=?]", @study.panes.first.frame_id
  end

  test "unknown book returns 404" do
    get cross_references_study_path(@study, osis: "Nope", chapter: 1, verse: 1)
    assert_response :not_found
  end

  test "a mirror request renders the requested passage without saving anything" do
    pane = @study.panes.first
    pane.update!(reference: "John 3:16", notes: "Original notes")
    patch study_pane_path(@study, pane),
          params: { mirror: "1", pane: { reference: "Romans 5:8", translation_id: @kjv.id, notes: "overwritten?" } }
    assert_response :success
    assert_includes response.body, "But God commendeth his love toward us"
    pane.reload
    assert_equal "John 3:16", pane.reference
    assert_equal "Original notes", pane.notes
    assert_nil pane.translation_id
  end

  test "signed-in users can save notes through the full pane form" do
    pane = @study.panes.first
    patch study_pane_path(@study, pane), params: { pane: { notes: "Kept without autosave" } }
    assert_response :success
    assert_equal "Kept without autosave", pane.reload.notes
  end

  test "notes autosave persists and returns no content" do
    pane = @study.panes.first
    patch study_pane_path(@study, pane), params: { autosave: "1", pane: { notes: "Hammer the perfect tense." } }
    assert_response :no_content
    assert_equal "Hammer the perfect tense.", pane.reload.notes
  end
end
