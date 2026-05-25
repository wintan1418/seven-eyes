class CreateReadingPlans < ActiveRecord::Migration[8.1]
  def change
    create_table :reading_plans do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.date :start_date, null: false
      t.bigint :study_id # optional: the workspace study tied to this plan
      t.timestamps
    end
    add_index :reading_plans, [ :user_id, :start_date ]
  end
end
