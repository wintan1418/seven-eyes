# Solid Cache's table, in the PRIMARY database — same reasoning as
# CreateSolidCableMessages: the production host only runs db:migrate for the
# primary schema, so the separate `cache` database from db/cache_schema.rb was
# never created. production.rb now uses :solid_cache_store (shared across Puma
# workers, so rate limits and AI spend guards actually hold).
class CreateSolidCacheEntries < ActiveRecord::Migration[8.1]
  def change
    return if table_exists?(:solid_cache_entries)

    create_table :solid_cache_entries do |t|
      t.binary :key, limit: 1024, null: false
      t.binary :value, limit: 536_870_912, null: false
      t.datetime :created_at, null: false
      t.integer :key_hash, limit: 8, null: false
      t.integer :byte_size, limit: 4, null: false

      t.index :byte_size
      t.index [ :key_hash, :byte_size ]
      t.index :key_hash, unique: true
    end
  end
end
