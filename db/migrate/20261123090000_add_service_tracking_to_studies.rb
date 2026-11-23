# Services that actually happened (the queue went live), so last Sunday's
# queue stops posing as this Sunday's:
#   last_served_at    first time anything from the queue went live, on the most
#                     recent day it was used (one ping per study per day)
#   service_kept_at   "Keep using it" — the operator chose to reuse a served queue
#   planned_for       a service started for a coming Sunday (Home "Plan this Sunday")
#   archived_at / archived_from_id / archive_key
#                     "Start fresh" moved a served queue into this copy (a past
#                     service, never This Sunday); archive_key is the device's id
#                     for that move, so a replayed request makes no second copy.
class AddServiceTrackingToStudies < ActiveRecord::Migration[8.1]
  def change
    change_table :studies, bulk: true do |t|
      t.datetime :last_served_at
      t.datetime :service_kept_at
      t.date :planned_for
      t.datetime :archived_at
      t.bigint :archived_from_id
      t.string :archive_key
    end
    add_index :studies, [ :user_id, :last_served_at ], where: "last_served_at IS NOT NULL"
    add_index :studies, :archive_key, unique: true, where: "archive_key IS NOT NULL"
    add_index :studies, :archived_from_id, where: "archived_from_id IS NOT NULL"
    add_foreign_key :studies, :studies, column: :archived_from_id, on_delete: :nullify
  end
end
