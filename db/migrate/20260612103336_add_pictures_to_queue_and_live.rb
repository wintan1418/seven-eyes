class AddPicturesToQueueAndLive < ActiveRecord::Migration[8.1]
  def change
    add_column :setlist_items, :media_url, :string
    add_column :setlist_items, :media_public_id, :string
    add_column :live_sessions, :slide_image_url, :string
  end
end
