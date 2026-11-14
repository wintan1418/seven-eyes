# One row per reader per day they finished "Today" (the guided daily flow on
# Home): the verse, the passage, a reflection, a word of the faith, a prayer,
# Amen. It gives a daily streak that doesn't depend on a reading plan.
class CreateDailyCompletions < ActiveRecord::Migration[8.1]
  def change
    create_table :daily_completions do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.date :date, null: false
      t.datetime :created_at, null: false
    end
    add_index :daily_completions, %i[ user_id date ], unique: true
  end
end
