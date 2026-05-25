class CreatePlanCompletions < ActiveRecord::Migration[8.1]
  def change
    create_table :plan_completions do |t|
      t.references :plan_day, null: false, foreign_key: true
      t.datetime :completed_at, null: false
      t.text :reflection # optional thought scribbled after reading
      t.timestamps
    end
    add_index :plan_completions, :plan_day_id, unique: true,
              name: "index_plan_completions_unique"
  end
end
