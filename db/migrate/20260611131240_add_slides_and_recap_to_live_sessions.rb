class AddSlidesAndRecapToLiveSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :live_sessions, :kind, :string, null: false, default: "scripture"
    add_column :live_sessions, :slide_title, :string
    add_column :live_sessions, :slide_body, :text
    add_column :live_sessions, :slide_index, :integer
    add_column :live_sessions, :passages, :jsonb, null: false, default: []
  end
end
