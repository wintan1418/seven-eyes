# A user's flag on a piece of AI-generated content. Stores a short excerpt of
# what the AI said, so it can be reviewed even when the answer isn't cached.
class AiReport < ApplicationRecord
  KINDS = %w[ rabbi illustration find_verse prayer daily_word ].freeze
  CONTEXT_LIMIT = 300
  EXCERPT_LIMIT = 4000

  belongs_to :user, optional: true

  validates :kind, inclusion: { in: KINDS }

  normalizes :context, with: ->(text) { text.to_s.squish.truncate(CONTEXT_LIMIT).presence }
  normalizes :excerpt, with: ->(text) { text.to_s.strip.truncate(EXCERPT_LIMIT).presence }

  scope :recent, -> { order(created_at: :desc) }
end
