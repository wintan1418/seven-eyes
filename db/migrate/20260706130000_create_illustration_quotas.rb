class CreateIllustrationQuotas < ActiveRecord::Migration[8.1]
  def change
    create_table :illustration_quotas do |t|
      t.string  :owner_key, null: false          # "u<user_id>" or "g<study_id>"
      t.date    :day,       null: false
      t.integer :count,     null: false, default: 0
      t.timestamps
    end
    add_index :illustration_quotas, [ :owner_key, :day ], unique: true
  end
end
