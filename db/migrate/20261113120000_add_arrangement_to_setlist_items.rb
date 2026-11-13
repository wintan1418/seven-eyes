class AddArrangementToSetlistItems < ActiveRecord::Migration[8.1]
  def change
    # A song's projection order, EasyWorship-style: "V1 C V2 C B C".
    add_column :setlist_items, :arrangement, :string
  end
end
