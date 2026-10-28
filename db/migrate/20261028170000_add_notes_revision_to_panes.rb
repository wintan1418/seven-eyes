# Offline note edits are replayed later; the revision tells the server whether
# the notes changed elsewhere in the meantime (see NotesSync).
class AddNotesRevisionToPanes < ActiveRecord::Migration[8.1]
  def change
    add_column :panes, :notes_revision, :integer, default: 0, null: false
  end
end
