class AddShareTokenToStudies < ActiveRecord::Migration[8.1]
  def change
    add_column :studies, :share_token, :string
    add_index :studies, :share_token, unique: true, where: "share_token IS NOT NULL"
  end
end
