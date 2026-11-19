# My Media: each account's picture library. A picture added to any service is
# kept here once (deduped by the file's MD5 checksum, the same value Active
# Storage keeps on the blob), and queue pictures point at it. The queue item
# keeps its own copy of the URL and its own attachment to the same blob, so a
# service never loses a picture when it is deleted from the library.
class CreateMediaAssets < ActiveRecord::Migration[8.1]
  def change
    create_table :media_assets do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.string :checksum
      t.bigint :byte_size, null: false, default: 0
      t.string :content_type
      t.integer :width
      t.integer :height
      t.string :media_url, null: false
      t.string :media_public_id
      t.jsonb :display, null: false, default: {}
      t.datetime :last_used_at
      t.timestamps
    end
    add_index :media_assets, %i[ user_id checksum ], unique: true, where: "checksum IS NOT NULL"
    add_index :media_assets, %i[ user_id media_url ]

    add_reference :setlist_items, :media_asset, foreign_key: { on_delete: :nullify }, index: true
  end
end
