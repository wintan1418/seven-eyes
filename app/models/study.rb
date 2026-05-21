class Study < ApplicationRecord
  belongs_to :user
  has_many :panes, -> { order(:position) }, dependent: :destroy, inverse_of: :study

  validates :name, presence: true
  validates :pane_count, inclusion: { in: 1..4 }

  after_create :build_default_panes

  scope :recent, -> { order(Arel.sql("last_opened_at DESC NULLS LAST, updated_at DESC")) }

  def touch_opened!
    update_column(:last_opened_at, Time.current)
  end

  # Ensure exactly pane_count panes exist (used when the count changes in Phase 3).
  def sync_panes!
    current = panes.to_a
    if current.size < pane_count
      (current.size...pane_count).each { |pos| panes.create!(position: pos) }
    elsif current.size > pane_count
      current[pane_count..].each(&:destroy)
    end
  end

  private

  def build_default_panes
    pane_count.times { |pos| panes.create!(position: pos) }
  end
end
