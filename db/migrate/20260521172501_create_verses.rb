class CreateVerses < ActiveRecord::Migration[8.1]
  def change
    create_table :verses do |t|
      t.references :translation, null: false, foreign_key: true
      t.references :book, null: false, foreign_key: true, index: false
      t.integer :chapter, null: false
      t.integer :verse_number, null: false
      t.text :text, null: false

      t.timestamps
    end
    add_index :verses, [ :translation_id, :book_id, :chapter, :verse_number ],
              unique: true, name: "index_verses_unique_location"
    add_index :verses, [ :book_id, :chapter ]
  end
end
