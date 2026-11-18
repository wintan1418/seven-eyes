class CreateDonations < ActiveRecord::Migration[8.1]
  def change
    create_table :donations do |t|
      t.integer :amount_minor, null: false
      t.string :currency, null: false, default: "NGN"
      t.string :frequency, null: false, default: "one_time"
      t.string :email, null: false
      t.string :name
      t.boolean :anonymous, null: false, default: false
      t.text :message
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :status, null: false, default: "pending"
      t.string :reference, null: false
      t.string :paystack_plan_code
      t.datetime :paid_at
      t.timestamps
    end
    add_index :donations, :reference, unique: true
    add_index :donations, [ :status, :paid_at ]
  end
end
