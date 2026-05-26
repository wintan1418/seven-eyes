class AddFontSizeToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :font_size, :integer, default: 0, null: false
  end
end
