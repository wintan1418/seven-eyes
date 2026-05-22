class Verse < ApplicationRecord
  belongs_to :translation
  belongs_to :book
  has_many :highlights, dependent: :destroy

  validates :chapter, :verse_number, :text, presence: true
  validates :verse_number,
            uniqueness: { scope: [ :translation_id, :book_id, :chapter ] }

  scope :ordered, -> { order(:chapter, :verse_number) }

  # Full-text search within one translation, ranked by relevance. Uses the
  # generated `text_vector` column (GIN-indexed). `websearch_to_tsquery` accepts
  # natural input ("love your enemies", quoted phrases, OR) and never raises on
  # garbage — a query with no usable terms simply matches nothing.
  def self.search(query, translation:, limit: 60)
    q = query.to_s.strip
    return none if q.blank?

    where(translation: translation)
      .where("text_vector @@ websearch_to_tsquery('english', :q)", q: q)
      .order(Arel.sql(sanitize_sql_array(
        [ "ts_rank(text_vector, websearch_to_tsquery('english', ?)) DESC", q ]
      )))
      .order(:chapter, :verse_number)
      .limit(limit)
      .includes(:book)
  end

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
