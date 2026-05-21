class CreateStudies < ActiveRecord::Migration[8.1]
  def change
    create_table :studies do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false, default: "Untitled Study"
      t.integer :pane_count, null: false, default: 4
      t.boolean :sync_scroll, null: false, default: false
      t.datetime :last_opened_at

      t.timestamps
    end
    add_index :studies, [ :user_id, :last_opened_at ]
  end
end
