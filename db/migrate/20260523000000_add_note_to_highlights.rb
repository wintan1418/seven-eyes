class AddNoteToHighlights < ActiveRecord::Migration[8.1]
  def change
    add_column :highlights, :note, :text
  end
end
