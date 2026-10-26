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
  # On failure `error` says why, with enough detail for the pane to explain:
  #   :empty            — no reference typed yet
  #   :unparseable      — ReferenceParser refused it (see parsed.error: :unknown_book / :bad_chapter / :bad_verse)
  #   :unknown_book     — parsed, but the book isn't seeded
  #   :verse_not_found  — the chapter exists but the asked-for verse(s) don't (max_verse says how many there are)
  #   :not_found        — this translation has no text for that chapter
  Content = Struct.new(:ok, :verses, :parsed, :translation, :book, :error, :max_verse, keyword_init: true) do
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
    return Content.new(ok: true, verses:, parsed:, translation: t, book:) if verses.any?

    # Nothing came back: distinguish "verse 30 of a 23-verse chapter" from a
    # chapter this translation simply doesn't have.
    max_verse = Verse.where(translation: t, book:, chapter: parsed.chapter).maximum(:verse_number)
    error = max_verse ? :verse_not_found : :not_found
    Content.new(ok: false, parsed:, translation: t, book:, error:, max_verse:)
  end
end
