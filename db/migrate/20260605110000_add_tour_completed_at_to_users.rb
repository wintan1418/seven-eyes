class AddTourCompletedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :tour_completed_at, :datetime
  end
end
