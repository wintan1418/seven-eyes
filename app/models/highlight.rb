class Highlight < ApplicationRecord
  belongs_to :user
  belongs_to :verse

  # Names match the design's over-vellum tints / .hl-* CSS classes.
  enum :color, { ochre: 0, sage: 1, cobalt: 2, rose: 3 }

  validates :char_start, :char_end, presence: true
  validate :sane_range
  # The same words highlighted twice (a double tap on a swatch, a retried
  # request) would stack identical spans. Overlapping-but-different ranges
  # are allowed; exact duplicates are not.
  validates :char_start, uniqueness: { scope: %i[user_id verse_id char_end],
                                       message: "already highlighted" }

  scope :ordered, -> { order(:char_start) }

  private

  def sane_range
    return if char_start.blank? || char_end.blank?
    errors.add(:char_end, "must be greater than char_start") if char_end <= char_start
    errors.add(:char_start, "must be non-negative") if char_start.negative?
  end
end
