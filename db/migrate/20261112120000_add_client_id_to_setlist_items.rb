# The preach queue is edited on the device first and synced in the background
# (outbox). Each item carries the id the device gave it so a replayed create
# (dropped connection, retry) finds the same row instead of adding a twin.
class AddClientIdToSetlistItems < ActiveRecord::Migration[8.1]
  def change
    add_column :setlist_items, :client_id, :string
    add_index :setlist_items, [ :study_id, :client_id ], unique: true, where: "client_id IS NOT NULL"
  end
end
