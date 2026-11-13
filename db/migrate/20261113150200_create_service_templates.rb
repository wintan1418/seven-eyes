# A whole service order kept for reuse ("Sunday Service", "Midweek"): a
# snapshot of the queue items, applied to a queue or used to start a new one.
class CreateServiceTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :service_templates do |t|
      t.references :user, null: false, foreign_key: true
      t.string :client_id, null: false
      t.string :name, null: false
      t.jsonb :items, null: false, default: []
      t.timestamps
    end
    add_index :service_templates, %i[ user_id client_id ], unique: true
  end
end
