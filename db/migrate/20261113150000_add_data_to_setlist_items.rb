# Structured content for the richer queue kinds: a scripture set's passages and
# layout (several references, each in its own translation, on one slide), and a
# presentation's deck key + page count (the pages stay on the device).
class AddDataToSetlistItems < ActiveRecord::Migration[8.1]
  def change
    add_column :setlist_items, :data, :jsonb, null: false, default: {}
  end
end
