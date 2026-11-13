class CreateSongs < ActiveRecord::Migration[8.1]
  def change
    # The account's own song bank: songs (or any custom slide) saved with
    # "Save to my songs", ready to queue in any study.
    create_table :songs do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.text :body
      t.string :arrangement
      t.string :author
      t.timestamps
    end
    add_index :songs, "user_id, lower(title)", unique: true, name: "index_songs_on_user_and_title"
  end
end
