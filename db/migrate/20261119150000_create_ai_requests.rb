# One row per AI question handed to the background worker (Quick Find, the
# Rabbi, an illustration). The request returns at once with a "thinking" state;
# the page polls the row until the job writes the answer. Rows are short-lived
# (AiRequest.prune! drops anything older than a day).
class CreateAiRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_requests do |t|
      t.string :token, null: false
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :study, null: false, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false
      t.string :status, null: false, default: "pending"
      t.string :fingerprint
      t.jsonb :params, null: false, default: {}
      t.jsonb :result
      t.string :error
      t.bigint :illustration_quota_id
      t.datetime :finished_at
      t.timestamps
    end
    add_index :ai_requests, :token, unique: true
    add_index :ai_requests, %i[user_id fingerprint status]
    add_index :ai_requests, :created_at
  end
end
