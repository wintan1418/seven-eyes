# "Today" — Home's guided daily flow, about five minutes, one calm step at a
# time: the verse (with Listen), the passage around it from our own Bible,
# the reflection, a word of the faith with its Greek/Hebrew root, the prayer,
# and Amen (which marks the day done — DailyCompletion).
#
# Built from what the app already has for the day: DailyWord (verse,
# reflection, prayer), FaithTerm.of_the_day (only terms the viewer may see —
# drafts stay with reviewers) and its first root word (LexiconEntry). Steps
# with nothing to show (no reflection composed yet, no reviewed glossary
# words) are left out. Four small queries; nothing here calls an AI.
class TodayFlow
  # Verses either side of the daily verse, and the most the passage shows.
  BEFORE = 2
  AFTER = 3
  MAX_VERSES = 10
  # Seconds a step takes, roughly — the "~5 min" on the Begin button.
  STEP_SECONDS = { verse: 40, passage: 90, reflection: 60, word: 40, prayer: 45, amen: 10 }.freeze

  PassageVerse = Data.define(:number, :text, :focus)

  attr_reader :word, :date

  def initialize(word, viewer: nil, date: DailyWord.today_date)
    @word = word
    @viewer = viewer
    @date = date
  end

  def steps
    @steps ||= [
      (:verse if word),
      (:passage if passage.size > word_span),
      (:reflection if word&.composed?),
      (:word if term),
      (:prayer if word&.prayer.present?),
      :amen
    ].compact
  end

  # "~5 min", never under 2.
  def minutes = [ (steps.sum { |s| STEP_SECONDS.fetch(s) } / 60.0).round, 2 ].max

  # The verses around the daily verse in the word's own translation (so the
  # words match the hero), the day's verses marked.
  def passage
    @passage ||= begin
      book = word && Book.find_by_osis(word.osis_code)
      translation = word && Translation.find_by(code: word.translation_code)
      if book && translation
        from, to = window
        Verse.where(translation:, book:, chapter: word.chapter, verse_number: from..to).order(:verse_number)
             .pluck(:verse_number, :text)
             .map { |n, text| PassageVerse.new(number: n, text:, focus: n.between?(word.verse_start, word.verse_end)) }
      else
        []
      end
    end
  end

  def passage_label
    return word&.reference if passage.empty?

    "#{word.book&.name || word.osis_code} #{word.chapter}:#{passage.first.number}–#{passage.last.number}"
  end

  # Today's glossary word for this viewer (reviewed only, unless a reviewer).
  def term
    return @term if defined?(@term)

    @term = FaithTerm.of_the_day(date, scope: FaithTerm.visible_to(@viewer))
  end

  def root
    return @root if defined?(@root)

    @root = term && term.root_strongs.first && LexiconEntry.find_by(strongs: term.root_strongs.first)
  end

  # The root's one-line meaning: the lexicon's short KJV gloss, else the
  # start of its definition.
  def root_meaning
    return nil unless root

    text = root.kjv_def.presence || root.definition.presence
    text&.squish&.truncate(110, separator: " ")
  end

  private

  def word_span = word ? word.verse_end - word.verse_start + 1 : 0

  def window
    room = [ MAX_VERSES - word_span, 0 ].max
    before = [ BEFORE, room / 2 ].min
    after = [ AFTER, room - before ].min
    [ [ word.verse_start - before, 1 ].max, word.verse_end + after ]
  end
end
