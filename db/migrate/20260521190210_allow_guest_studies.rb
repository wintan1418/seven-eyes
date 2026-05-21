class AllowGuestStudies < ActiveRecord::Migration[8.1]
  def change
    change_column_null :studies, :user_id, true
  end
end
