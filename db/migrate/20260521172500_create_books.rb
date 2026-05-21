class CreateBooks < ActiveRecord::Migration[8.1]
  def change
    create_table :books do |t|
      t.string :osis_code, null: false
      t.string :name, null: false
      t.integer :testament, null: false
      t.integer :position, null: false
      t.integer :chapter_count, null: false

      t.timestamps
    end
    add_index :books, :osis_code, unique: true
    add_index :books, :position, unique: true
  end
end
