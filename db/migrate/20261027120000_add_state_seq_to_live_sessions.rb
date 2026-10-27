# Monotonic sequence number for operator state pushes. The console stamps
# every PATCH; the server ignores any push older than the last one it applied,
# so a slow request can never drag the congregation back to a stale verse.
class AddStateSeqToLiveSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :live_sessions, :state_seq, :bigint, default: 0, null: false
  end
end
