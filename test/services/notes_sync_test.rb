require "test_helper"

class NotesSyncTest < ActiveSupport::TestCase
  setup do
    study = users(:one).studies.create!(name: "Sunday", pane_count: 1)
    @pane = study.panes.first
    @pane.update!(notes: "Grace first.")
    @base = @pane.reload.notes_revision
  end

  test "every change to the notes bumps the revision; other edits don't" do
    before = @pane.notes_revision
    @pane.update!(reference: "John 3")
    assert_equal before, @pane.reload.notes_revision
    @pane.update!(notes: "Changed")
    assert_equal before + 1, @pane.reload.notes_revision
  end

  test "an offline edit built on the current revision simply saves" do
    result = NotesSync.call(pane: @pane, text: "Grace first. Then faith.", base_revision: @base)
    assert_not result.conflict?
    assert_equal "Grace first. Then faith.", @pane.reload.notes
    assert_equal @base + 1, result.revision
  end

  test "if the server copy changed meanwhile, the offline text is added below a divider" do
    @pane.update!(notes: "Grace first. (edited on the laptop)")
    result = NotesSync.call(pane: @pane, text: "Grace first. Written on the bus.",
                            base_revision: @base, edited_at: "2026-10-26T09:30:00Z")
    assert result.conflict?
    assert_equal "Grace first. (edited on the laptop)\n\n— Offline edit (Oct 26, 2026) —\nGrace first. Written on the bus.",
                 @pane.reload.notes
    assert_equal result.notes, @pane.notes
  end

  test "replaying the same offline edit twice doesn't add it twice" do
    @pane.update!(notes: "Server copy")
    NotesSync.call(pane: @pane, text: "Offline copy", base_revision: @base)
    merged = @pane.reload.notes
    again = NotesSync.call(pane: @pane, text: "Offline copy", base_revision: @base)
    assert_not again.conflict?
    assert_equal merged, @pane.reload.notes
  end

  test "an offline edit onto empty server notes just saves the text" do
    @pane.update!(notes: "")
    result = NotesSync.call(pane: @pane, text: "New thought", base_revision: @base)
    assert_not result.conflict?
    assert_equal "New thought", @pane.reload.notes
  end

  test "live autosaves without a base revision stay last-write-wins" do
    @pane.update!(notes: "Elsewhere")
    result = NotesSync.call(pane: @pane, text: "Mine")
    assert_not result.conflict?
    assert_equal "Mine", @pane.reload.notes
  end
end
