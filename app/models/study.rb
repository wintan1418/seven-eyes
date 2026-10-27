class Study < ApplicationRecord
  belongs_to :user, optional: true # nil = a guest's session-scoped study
  # Every pane ever made for this study, including ones hidden when the pane
  # count was lowered. Hidden panes keep their reference and notes so raising
  # the count brings them back intact — lowering the count must never destroy
  # a pastor's notes.
  has_many :all_panes, -> { order(:position) }, class_name: "Pane", dependent: :destroy, inverse_of: :study
  # The panes on screen: only the first pane_count positions.
  has_many :panes, ->(study) { where(position: ...study.pane_count).order(:position) }, inverse_of: :study
  has_many :live_sessions, dependent: :destroy
  has_many :setlist_items, dependent: :destroy

  def live_session
    live_sessions.active.order(created_at: :desc).first
  end

  validates :name, presence: true
  validates :pane_count, inclusion: { in: 1..4 }

  after_create :build_default_panes

  scope :recent, -> { order(Arel.sql("last_opened_at DESC NULLS LAST, updated_at DESC")) }

  def touch_opened!
    update_column(:last_opened_at, Time.current)
  end

  # Lazily generate a URL-safe share token. Idempotent — repeat calls return
  # the same token so a shared link stays stable.
  def ensure_share_token!
    return share_token if share_token.present?
    loop do
      candidate = SecureRandom.urlsafe_base64(16)
      update_column(:share_token, candidate)
      return candidate
    rescue ActiveRecord::RecordNotUnique
      next
    end
  end

  # Ensure a pane exists at every visible position (0...pane_count). Never
  # destroys anything: panes beyond the count stay in the database, hidden, with
  # their notes, and reappear when the count is raised again.
  def sync_panes!
    existing = all_panes.reload.map(&:position)
    (0...pane_count).each do |pos|
      all_panes.create!(position: pos) unless existing.include?(pos)
    end
    panes.reset
  end

  private

  def build_default_panes
    pane_count.times { |pos| all_panes.create!(position: pos) }
  end
end
