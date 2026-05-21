class CreateHighlights < ActiveRecord::Migration[8.1]
  def change
    create_table :highlights do |t|
      t.references :user, null: false, foreign_key: true
      t.references :verse, null: false, foreign_key: true
      t.integer :color, null: false, default: 0
      t.integer :char_start, null: false
      t.integer :char_end, null: false

      t.timestamps
    end
    add_index :highlights, [ :user_id, :verse_id ]
  end
end
