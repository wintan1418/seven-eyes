# Glossary of the Faith — /faith (A–Z, searchable) and /faith/:slug.
#
# A two-pane reader from 1024px: the side pane (search, A–Z, every term) stays
# put while the term opens in the "ft-content" Turbo Frame beside it. A frame
# request only needs the frame, so the side pane's list isn't loaded for it.
# On a phone the same markup is the list (/faith) → term page flow.
#
# Public, no login. Only reviewed terms are shown, except to admins and
# reviewers (User#faith_reviewer?), who also see drafts with a badge. With no
# visible terms the glossary doesn't exist yet: both pages are a 404.
class FaithTermsController < ApplicationController
  allow_unauthenticated_access

  SAMPLE_VERSES = 3
  STARTERS = 6

  def index
    @terms = visible_terms.alphabetical.to_a
    raise ActiveRecord::RecordNotFound if @terms.empty?

    @letters = @terms.group_by(&:letter)
    @word = FaithTerm.of_the_day(DailyWord.today_date, scope: visible_terms)
    @word_root = @word&.root_entries&.first
    @starters = visible_terms.in_order.where.not(id: @word&.id).limit(STARTERS)
  end

  def show
    @term = visible_terms.find_by!(slug: params[:slug])
    @letters = visible_terms.alphabetical.group_by(&:letter) unless turbo_frame_request?
    @translation = KeyPassages.default_translation
    @passages = KeyPassages.call(@term.key_references, translation: @translation)
    @roots = @term.root_entries.map { |entry| root_word(entry) }
    @related = @term.related_terms(visible_terms)
  end

  private

  def visible_terms
    FaithTerm.visible_to(authenticated? ? current_user : nil)
  end

  # One root word: its lexicon entry, how many KJV verses use it, and a few of
  # them to open in the reader.
  def root_word(entry)
    verses = @translation ? Verse.with_strongs(entry.strongs).where(translation: @translation) : Verse.none
    samples = verses.joins(:book).includes(:book)
                    .order("books.position", "verses.chapter", "verses.verse_number").limit(SAMPLE_VERSES)
    { entry:, count: verses.count, samples: }
  end
end
