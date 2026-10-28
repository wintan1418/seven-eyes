# Saves a pane's notes, guarding notes written offline against overwriting
# newer ones.
#
# Every change to a pane's notes bumps panes.notes_revision. An edit made
# offline is replayed later with the revision it started from
# (base_revision). If the notes changed on the server since — another device,
# another tab — the server copy is kept and the offline text is appended
# below a clear divider instead of replacing it:
#
#   …the server's notes…
#
#   — Offline edit (Oct 28, 2026) —
#   …the text written offline…
#
# Live autosaves (no base_revision) keep last-write-wins, as before.
class NotesSync
  Result = Struct.new(:notes, :revision, :conflict, keyword_init: true) do
    def conflict? = conflict
  end

  def self.call(pane:, text:, base_revision: nil, edited_at: nil)
    new(pane:, text:, base_revision:, edited_at:).call
  end

  def initialize(pane:, text:, base_revision:, edited_at:)
    @pane = pane
    @text = text.to_s
    @base_revision = base_revision.presence&.to_i
    @edited_at = parse_time(edited_at)
  end

  def call
    @pane.with_lock do
      server = @pane.notes.to_s
      moved_on = !@base_revision.nil? && @base_revision != @pane.notes_revision
      conflict = false

      if !moved_on || server.strip.empty?
        @pane.update!(notes: @text)
      elsif @text != server && !server.include?(@text.strip) # (already merged: a retried replay)
        @pane.update!(notes: merge(server))
        conflict = true
      end
      Result.new(notes: @pane.notes.to_s, revision: @pane.notes_revision, conflict:)
    end
  end

  def self.divider(time)
    "— Offline edit (#{time.strftime('%b %-d, %Y')}) —"
  end

  private

  def merge(server)
    [ server.rstrip, "", self.class.divider(@edited_at || Time.current), @text.strip ].join("\n")
  end

  def parse_time(value)
    Time.zone.parse(value.to_s) if value.present?
  rescue ArgumentError
    nil
  end
end
