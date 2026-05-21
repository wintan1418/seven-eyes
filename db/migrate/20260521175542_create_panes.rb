class CreatePanes < ActiveRecord::Migration[8.1]
  def change
    create_table :panes do |t|
      t.references :study, null: false, foreign_key: true
      t.integer :position, null: false, default: 0
      t.references :translation, null: true, foreign_key: true
      t.string :reference
      t.text :notes

      t.timestamps
    end
    add_index :panes, [ :study_id, :position ], unique: true
  end
end
