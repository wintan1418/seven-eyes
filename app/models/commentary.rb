class Commentary < ApplicationRecord
  belongs_to :book

  validates :source, :source_name, :body, presence: true
  validates :chapter, presence: true, numericality: { greater_than: 0 }
  validates :source, uniqueness: { scope: [ :book_id, :chapter ] }

  scope :for_chapter, ->(book, chapter) { where(book:, chapter:).order(:source_name) }
end
