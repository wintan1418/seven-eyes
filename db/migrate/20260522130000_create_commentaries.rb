class CreateCommentaries < ActiveRecord::Migration[8.1]
  def change
    create_table :commentaries do |t|
      t.string :source, null: false
      t.string :source_name, null: false
      t.references :book, null: false, foreign_key: true
      t.integer :chapter, null: false
      t.text :body, null: false
      t.timestamps
    end
    add_index :commentaries, [ :source, :book_id, :chapter ], unique: true, name: "index_commentaries_unique"
    add_index :commentaries, [ :book_id, :chapter ], name: "index_commentaries_on_book_and_chapter"
  end
end
