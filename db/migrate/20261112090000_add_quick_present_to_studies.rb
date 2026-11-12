# Quick Present: one always-ready personal study per user that the device
# keeps offline, so a presenter can start projecting with no internet.
class AddQuickPresentToStudies < ActiveRecord::Migration[8.1]
  def change
    add_column :studies, :quick_present, :boolean, default: false, null: false
    add_index :studies, :user_id, unique: true, where: "quick_present", name: "index_studies_one_quick_present_per_user"
  end
end
