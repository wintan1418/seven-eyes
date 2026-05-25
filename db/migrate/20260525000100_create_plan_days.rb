class CreatePlanDays < ActiveRecord::Migration[8.1]
  def change
    create_table :plan_days do |t|
      t.references :reading_plan, null: false, foreign_key: true
      t.integer :day_number, null: false
      t.text :refs, null: false, default: "" # comma-separated list of references
      t.timestamps
    end
    add_index :plan_days, [ :reading_plan_id, :day_number ], unique: true,
              name: "index_plan_days_unique"
  end
end
