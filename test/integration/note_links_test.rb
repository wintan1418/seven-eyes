require "test_helper"

class NoteLinksTest < ActionDispatch::IntegrationTest
  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @john = Book.create!(osis_code: "John", name: "John", testament: :new,
                         position: 43, chapter_count: 21)
    @rom  = Book.create!(osis_code: "Rom",  name: "Romans", testament: :new,
                         position: 45, chapter_count: 16)
    Verse.create!(translation: @kjv, book: @john, chapter: 3, verse_number: 16,
                  text: "For God so loved the world.")
    Verse.create!(translation: @kjv, book: @rom,  chapter: 5, verse_number: 1,
                  text: "Therefore being justified by faith.")

    @user = users(:one)
    sign_in_as @user
    @study = @user.studies.create!(name: "Linked", pane_count: 1)
    @study.panes.first.update!(reference: "John 3:16", translation: @kjv,
                               notes: "Echoes of [[Jn 3:16]] reverberate in [[Rom 5:1]].")
  end

  test "sermon manuscript renders [[ref]] tokens as anchor tags into the xref drawer" do
    get sermon_study_path(@study)
    assert_response :success
    assert_select "a.ps-note-link", text: "[[John 3:16]]"
    assert_select "a.ps-note-link", text: "[[Romans 5:1]]"
    assert_select "a.ps-note-link[data-turbo-frame='xref_drawer']"
  end

  test "invalid [[ref]] tokens fall through as escaped plain text" do
    @study.panes.first.update!(notes: "Try [[nonsense ref]] here.")
    get sermon_study_path(@study)
    assert_response :success
    assert_select "a.ps-note-link", count: 0
    assert_match(/\[\[nonsense ref\]\]/, @response.body)
  end

  test "xref drawer surfaces backlinks for the verse" do
    # Build a SECOND study that mentions John 3:16 — backlinks list it.
    other = @user.studies.create!(name: "Cross-pollination", pane_count: 1)
    other.panes.first.update!(notes: "Connect to [[John 3:16]] as anchor.")

    get cross_references_study_path(@study, osis: "John", chapter: 3, verse: 16,
                                    translation: "KJV"), as: :html,
        headers: { "Turbo-Frame" => "xref_drawer" }
    assert_response :success
    assert_select ".ps-backlinks-head", text: /In your notes/
    assert_select ".ps-backlink-meta .study", text: /Linked|Cross-pollination/
  end

  test "xref drawer omits backlinks panel when the user has no matching notes" do
    @study.panes.first.update!(notes: nil)
    get cross_references_study_path(@study, osis: "John", chapter: 3, verse: 16,
                                    translation: "KJV"), as: :html,
        headers: { "Turbo-Frame" => "xref_drawer" }
    assert_response :success
    assert_select ".ps-backlinks", count: 0
  end
end
