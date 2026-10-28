require "test_helper"

# Writes made offline are replayed by the outbox (app/javascript/lib/offline/outbox.js).
# These pin what the server tells it back.
class OfflineSyncTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @study = @user.studies.create!(name: "Sunday", pane_count: 1)
    @pane = @study.panes.first
    @pane.update!(notes: "Server text")
  end

  test "a live autosave reports the new notes revision" do
    sign_in_as @user
    patch study_pane_path(@study, @pane), params: { autosave: "1", pane: { notes: "Typed online" } }
    assert_response :no_content
    assert_equal @pane.reload.notes_revision.to_s, response.headers["X-Notes-Revision"]
  end

  test "the pane's notes form carries the revision it was rendered with" do
    sign_in_as @user
    @pane.update!(reference: "John 3")
    kjv = Translation.create!(code: "KJV", name: "King James Version")
    john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    Verse.create!(translation: kjv, book: john, chapter: 3, verse_number: 16, text: "For God so loved")
    get study_path(@study)
    assert_select "form.ps-notes-form[data-notes-revision-value='#{@pane.reload.notes_revision}']"
  end

  test "a replayed offline note built on the current revision saves and says so" do
    sign_in_as @user
    base = @pane.notes_revision
    patch study_pane_path(@study, @pane),
          params: { autosave: "1", base_revision: base, edited_at: "2026-10-26T09:00:00Z", pane: { notes: "Server text + offline" } },
          headers: { "Accept" => "application/json" }
    assert_response :success
    assert_equal({ "notes" => "Server text + offline", "revision" => base + 1, "conflict" => false }, response.parsed_body)
  end

  test "a replayed offline note never overwrites newer notes" do
    sign_in_as @user
    base = @pane.notes_revision
    @pane.update!(notes: "Edited on another device")
    patch study_pane_path(@study, @pane),
          params: { autosave: "1", base_revision: base, edited_at: "2026-10-26T09:00:00Z", pane: { notes: "Written offline" } },
          headers: { "Accept" => "application/json" }
    body = response.parsed_body
    assert body["conflict"]
    assert_equal "Edited on another device\n\n— Offline edit (Oct 26, 2026) —\nWritten offline", @pane.reload.notes
    assert_equal @pane.notes, body["notes"]
  end

  test "guests can't replay notes or highlights (same as online)" do
    post studies_path
    guest_study = Study.where(user_id: nil).order(:id).last
    patch study_pane_path(guest_study, guest_study.panes.first), params: { autosave: "1", base_revision: 0, pane: { notes: "x" } }
    assert_response :unauthorized
    post highlights_path, params: { highlight: { verse_id: 1, color: "sage", char_start: 0, char_end: 2 } }, as: :json
    assert_response :unauthorized
  end
end
