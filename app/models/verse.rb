class Verse < ApplicationRecord
  belongs_to :translation
  belongs_to :book
  has_many :highlights, dependent: :destroy

  validates :chapter, :verse_number, :text, presence: true
  validates :verse_number,
            uniqueness: { scope: [ :translation_id, :book_id, :chapter ] }

  scope :ordered, -> { order(:chapter, :verse_number) }

  # Load a contiguous range in a single query. Pass nil ends for open ranges.
  def self.passage(translation:, book:, chapter:, verse_start: nil, verse_end: nil)
    rel = where(translation:, book:, chapter:).ordered
    rel = rel.where(verse_number: verse_start..(verse_end || verse_start)) if verse_start
    rel
  end

  def label
    "#{book.name} #{chapter}:#{verse_number}"
  end
end
