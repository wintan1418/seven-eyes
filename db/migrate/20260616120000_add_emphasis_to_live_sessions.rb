class AddEmphasisToLiveSessions < ActiveRecord::Migration[8.1]
  def change
    # The minister's emphasised words for the current verse, keyed by verse
    # number → word indices. Stored so a phone that reconnects mid-service
    # restores the glow on resync, not just on the next verse change.
    add_column :live_sessions, :emphasis, :jsonb, null: false, default: {}
  end
end
