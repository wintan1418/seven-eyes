class CreateCrossReferences < ActiveRecord::Migration[8.1]
  def change
    create_table :cross_references do |t|
      t.references :from_book, null: false, foreign_key: { to_table: :books }, index: false
      t.integer :from_chapter, null: false
      t.integer :from_verse, null: false
      t.references :to_book, null: false, foreign_key: { to_table: :books }
      t.integer :to_chapter_start, null: false
      t.integer :to_verse_start, null: false
      t.integer :to_chapter_end
      t.integer :to_verse_end
      t.integer :votes, null: false, default: 0

      t.timestamps
    end
    add_index :cross_references, [ :from_book_id, :from_chapter, :from_verse ],
              name: "index_xrefs_on_from_location"
  end
end
