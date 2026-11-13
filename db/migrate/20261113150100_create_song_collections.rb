# The song bank's own collections ("Communion", "Christmas", "Choir"). A
# collection lists songs by title, so it can hold hymnal songs as well as the
# account's own. Keyed by the device's id (client_id) so an offline change
# replays as an idempotent upsert.
class CreateSongCollections < ActiveRecord::Migration[8.1]
  def change
    create_table :song_collections do |t|
      t.references :user, null: false, foreign_key: true
      t.string :client_id, null: false
      t.string :name, null: false
      t.jsonb :titles, null: false, default: []
      t.timestamps
    end
    add_index :song_collections, %i[ user_id client_id ], unique: true
  end
end
