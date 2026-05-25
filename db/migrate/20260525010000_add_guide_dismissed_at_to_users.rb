class AddGuideDismissedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :guide_dismissed_at, :datetime
  end
end
