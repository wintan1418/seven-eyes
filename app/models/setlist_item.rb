# One entry in a study's preach queue (the service "setlist"): the planned
# order of what goes on the big screen. Three kinds:
#   scripture — a reference, chased through the presented pane like the Go box
#   song      — title + lyrics; blank lines split the body into stanza slides
#   thought   — a freeform note/announcement projected as a single slide
class SetlistItem < ApplicationRecord
  belongs_to :study

  enum :kind, { scripture: 0, song: 1, thought: 2 }

  validates :position, presence: true
  validates :reference, presence: true, if: :scripture?
  validate :reference_must_parse, if: :scripture?
  validate :slide_must_have_content, unless: :scripture?

  scope :in_order, -> { order(:position, :id) }

  before_create :assign_position

  # What the queue list shows for this item.
  def label
    return parsed&.label || reference if scripture?
    title.presence || body.to_s.strip.lines.first.to_s.strip.truncate(60)
  end

  def parsed
    return nil unless scripture? && reference.present?
    @parsed ||= ReferenceParser.call(reference)
  end

  # Lyrics/thought body split into stanza slides on blank lines.
  def stanzas
    body.to_s.split(/\n{2,}/).map(&:strip).reject(&:empty?)
  end

  # Swap with the neighbour above/below, renumbering the whole list so
  # positions stay dense no matter what was deleted in between.
  def move!(direction)
    siblings = study.setlist_items.in_order.to_a
    idx = siblings.index { |s| s.id == id }
    other = direction.to_s == "up" ? idx - 1 : idx + 1
    return if idx.nil? || other.negative? || other >= siblings.size
    siblings[idx], siblings[other] = siblings[other], siblings[idx]
    transaction do
      siblings.each_with_index { |s, i| s.update_column(:position, i) }
    end
  end

  private

  def assign_position
    self.position = (study.setlist_items.maximum(:position) || -1) + 1
  end

  def reference_must_parse
    return if reference.blank?
    parsed_ref = ReferenceParser.call(reference)
    unless parsed_ref.valid? && Book.find_by_osis(parsed_ref.osis)
      errors.add(:reference, "couldn't be read — try something like John 3:16")
    end
  end

  def slide_must_have_content
    errors.add(:base, "Give it a title or some words") if title.blank? && body.blank?
  end
end
