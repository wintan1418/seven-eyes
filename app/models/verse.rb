class Verse < ApplicationRecord
  belongs_to :translation
  belongs_to :book
  has_many :highlights, dependent: :destroy

  validates :chapter, :verse_number, :text, presence: true
  validates :verse_number,
            uniqueness: { scope: [ :translation_id, :book_id, :chapter ] }

  scope :ordered, -> { order(:chapter, :verse_number) }

  # Verses whose word tokens include a given Strong's number (KJV is tagged).
  scope :with_strongs, ->(strongs) { where("tokens @> ?", [ { s: strongs.to_s.upcase } ].to_json) }

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
  #
  #   passage(chapter: 3, verse_start: 16, verse_end: 18)                 John 3:16-18
  #   passage(chapter: 3, verse_start: 16, chapter_end: 4, verse_end: 2)  John 3:16-4:2
  #   passage(chapter: 5, chapter_end: 7)                                  Matthew 5-7
  #   passage(chapter: 3, verse_start: 16, verse_end: Float::INFINITY)    John 3:16ff
  #
  # A span across chapters compares (chapter, verse_number) as a row, so it
  # takes the tail of the first chapter and the head of the last in one query.
  def self.passage(translation:, book:, chapter:, verse_start: nil, verse_end: nil, chapter_end: nil)
    if chapter_end.nil? || chapter_end <= chapter
      rel = where(translation:, book:, chapter:).ordered
      return verse_start ? rel.where(verse_number: verse_start..(verse_end || verse_start)) : rel
    end

    rel = where(translation:, book:, chapter: chapter..chapter_end).ordered
    rel = rel.where("(chapter, verse_number) >= (?, ?)", chapter, verse_start) if verse_start
    if verse_end && verse_end != Float::INFINITY
      rel = rel.where("(chapter, verse_number) <= (?, ?)", chapter_end, verse_end)
    end
    rel
  end

  # Verses for a parsed ReferenceParser::Result (single verse, range, open
  # "ff" range, cross-chapter span or run of whole chapters).
  def self.for_reference(parsed, translation:, book:)
    passage(translation:, book:, **parsed.passage_args)
  end

  def label
    "#{book.name} #{chapter}:#{verse_number}"
  end

  # Typographic variants that differ between our text and the Strong's-tagged
  # KJV source ("mother’s" / "mother's", "Judæa" / "Judaea").
  FOLD = { "’" => "'", "‘" => "'", "“" => '"', "”" => '"', "æ" => "ae", "Æ" => "Ae",
           "œ" => "oe", "Œ" => "Oe", "–" => "-", "—" => "-" }.freeze

  def self.fold_char(char) = FOLD.fetch(char, char)

  # Text reduced for comparing wordings: whitespace dropped, typography folded.
  def self.comparable_text(str)
    str.to_s.gsub(/\s+/, "").each_char.map { |c| fold_char(c) }.join
  end
end
