class Pane < ApplicationRecord
  belongs_to :study
  belongs_to :translation, optional: true

  validates :position, presence: true

  # Every change to the notes gets a new revision, so a note written offline
  # can tell whether the server copy moved on meanwhile (see NotesSync).
  before_save :bump_notes_revision, if: :will_save_change_to_notes?

  DEFAULT_TRANSLATION = "KJV".freeze

  def frame_id = "pane_#{id}"

  def bump_notes_revision
    self.notes_revision = notes_revision.to_i + 1
  end

  def empty? = reference.blank?

  # The pane's chosen translation when it is one we offer; otherwise the
  # default (KJV), otherwise the first offered. A pane saved with a translation
  # that has since been withdrawn (NET) or is incomplete never renders blank.
  def effective_translation
    return translation if translation && Translation.available.exists?(translation.id)
    Translation.default
  end

  # Resolved verses for this pane's reference + translation, in a single query.
  # On failure `error` says why, with enough detail for the pane to explain:
  #   :empty            — no reference typed yet
  #   :unparseable      — ReferenceParser refused it (see parsed.error: :unknown_book / :bad_chapter / :bad_verse)
  #   :unknown_book     — parsed, but the book isn't seeded
  #   :no_translation   — no translation is seeded on this server at all
  #   :verse_omitted    — the verse is inside the chapter's numbering but this translation
  #                       leaves it out (Matt 18:11 in the BSB); `alternative` has it
  #   :verse_not_found  — the chapter exists but the asked-for verse(s) don't (max_verse says how many there are)
  #   :not_found        — this translation has no text for that chapter; `alternative` does
  # On success `missing` lists [chapter, verse] gaps inside the shown span (verses this
  # translation omits) and `alternative` is a translation that carries them.
  Content = Struct.new(:ok, :verses, :parsed, :translation, :book, :error, :max_verse, :missing, :alternative,
                       keyword_init: true) do
    def ok? = ok
    def chapters = Array(verses).map(&:chapter).uniq
    def first_chapter = chapters.first || parsed&.chapter
    def last_chapter = chapters.last || parsed&.last_chapter
    def multi_chapter? = chapters.size > 1
  end

  def content
    return Content.new(ok: false, error: :empty) if empty?

    parsed = ReferenceParser.call(reference)
    return Content.new(ok: false, parsed:, error: :unparseable) unless parsed.valid?

    book = Book.find_by_osis(parsed.osis)
    return Content.new(ok: false, parsed:, error: :unknown_book) unless book

    t = effective_translation
    return Content.new(ok: false, parsed:, book:, error: :no_translation) unless t

    verses = Verse.for_reference(parsed, translation: t, book:).includes(:translation).to_a
    if verses.any?
      missing = PassageGaps.within(verses, parsed)
      alternative = PassageGaps.alternative_for(book:, translation: t, locations: missing) if missing.any?
      return Content.new(ok: true, verses:, parsed:, translation: t, book:, missing:, alternative:)
    end

    # Nothing came back. Tell apart: a chapter this translation doesn't carry,
    # a verse it leaves out (another translation has it), and a verse past the
    # end of the chapter.
    max_verse = Verse.where(translation: t, book:, chapter: parsed.chapter).maximum(:verse_number)
    unless max_verse
      alternative = PassageGaps.alternative_for(book:, translation: t, chapter: parsed.chapter)
      return Content.new(ok: false, parsed:, translation: t, book:, error: :not_found, alternative:)
    end

    if parsed.verse_start
      wanted = [ [ parsed.chapter, parsed.verse_start ] ]
      alternative = PassageGaps.alternative_for(book:, translation: t, locations: wanted)
      if alternative
        return Content.new(ok: false, parsed:, translation: t, book:, error: :verse_omitted,
                           max_verse:, missing: wanted, alternative:)
      end
    end
    Content.new(ok: false, parsed:, translation: t, book:, error: :verse_not_found, max_verse:)
  end
end
