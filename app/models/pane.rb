class Pane < ApplicationRecord
  belongs_to :study
  belongs_to :translation, optional: true

  validates :position, presence: true

  DEFAULT_TRANSLATION = "KJV".freeze

  def frame_id = "pane_#{id}"

  def empty? = reference.blank?

  def effective_translation
    translation || Translation.find_by(code: DEFAULT_TRANSLATION) || Translation.first
  end

  # Resolved verses for this pane's reference + translation, in a single query.
  Content = Struct.new(:ok, :verses, :parsed, :translation, :book, :error, keyword_init: true) do
    def ok? = ok
  end

  def content
    return Content.new(ok: false, error: :empty) if empty?

    parsed = ReferenceParser.call(reference)
    return Content.new(ok: false, parsed:, error: :unparseable) unless parsed.valid?

    book = Book.find_by_osis(parsed.osis)
    return Content.new(ok: false, parsed:, error: :unknown_book) unless book

    t = effective_translation
    verses = Verse.passage(translation: t, book:, chapter: parsed.chapter,
                           verse_start: parsed.verse_start, verse_end: parsed.verse_end).to_a
    return Content.new(ok: false, parsed:, translation: t, book:, error: :not_found) if verses.empty?

    Content.new(ok: true, verses:, parsed:, translation: t, book:)
  end
end
