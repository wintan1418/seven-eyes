class Highlight < ApplicationRecord
  belongs_to :user
  belongs_to :verse

  # Names match the design's over-vellum tints / .hl-* CSS classes.
  enum :color, { ochre: 0, sage: 1, cobalt: 2, rose: 3 }

  validates :char_start, :char_end, presence: true
  validate :sane_range

  scope :ordered, -> { order(:char_start) }

  private

  def sane_range
    return if char_start.blank? || char_end.blank?
    errors.add(:char_end, "must be greater than char_start") if char_end <= char_start
    errors.add(:char_start, "must be non-negative") if char_start.negative?
  end
end
