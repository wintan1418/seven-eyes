class CreateSetlistItems < ActiveRecord::Migration[8.1]
  def change
    create_table :setlist_items do |t|
      t.references :study, null: false, foreign_key: true
      t.integer :position, null: false, default: 0
      t.integer :kind, null: false, default: 0
      t.string :reference
      t.string :title
      t.text :body

      t.timestamps
    end
    add_index :setlist_items, %i[study_id position]
  end
end
