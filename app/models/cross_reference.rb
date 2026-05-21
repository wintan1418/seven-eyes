class CrossReference < ApplicationRecord
  belongs_to :from_book, class_name: "Book"
  belongs_to :to_book, class_name: "Book"

  validates :from_chapter, :from_verse, :to_chapter_start, :to_verse_start, presence: true

  scope :by_confidence, -> { order(votes: :desc) }

  # All references originating at a given verse, best first.
  scope :for_verse, ->(book_id:, chapter:, verse:) {
    where(from_book_id: book_id, from_chapter: chapter, from_verse: verse).by_confidence
  }

  def to_label
    label = "#{to_book.name} #{to_chapter_start}:#{to_verse_start}"
    if to_verse_end && (to_chapter_end.nil? || to_chapter_end == to_chapter_start)
      label += "-#{to_verse_end}" if to_verse_end != to_verse_start
    elsif to_chapter_end
      label += "-#{to_chapter_end}:#{to_verse_end}"
    end
    label
  end
end
