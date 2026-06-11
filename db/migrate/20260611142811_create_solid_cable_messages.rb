# Solid Cable's pub/sub table, in the PRIMARY database. The production host
# only runs db:migrate for the primary schema (see the cache/queue notes in
# production.rb), so the separate `cable` database from db/cable_schema.rb was
# never created — which silently killed every Action Cable feature in
# production (Go Live, phone remote). cable.yml now points Solid Cable at the
# primary database, and this migration provides its table.
class CreateSolidCableMessages < ActiveRecord::Migration[8.1]
  def change
    return if table_exists?(:solid_cable_messages)

    create_table :solid_cable_messages do |t|
      t.binary :channel, limit: 1024, null: false
      t.binary :payload, limit: 536_870_912, null: false
      t.datetime :created_at, null: false
      t.integer :channel_hash, limit: 8, null: false

      t.index :channel
      t.index :channel_hash
      t.index :created_at
    end
  end
end
