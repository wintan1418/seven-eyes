# "Word for Today": one Scripture passage per calendar day with a short
# AI-written reflection and prayer.
#
# The row for a day is created lazily by the first request that day (or by the
# early-morning recurring job). The passage comes from a curated list and its
# words are copied from our own DB; the reflection and prayer are composed in
# the background by DailyWordComposer. Until they arrive — or if AI is switched
# off, out of budget or failing — the word shows the verse alone with a gentle
# fallback line. The page never waits on, or errors because of, the AI.
class DailyWord < ApplicationRecord
  # One day boundary for everyone: the app's home congregation is in Nigeria.
  TIME_ZONE = "Africa/Lagos".freeze

  # The curated "verse of the day" list, extended with short, well-loved
  # passages so a word never repeats within REFERENCES.size days.
  REFERENCES = (DailyVerse::REFERENCES + [
    "Psalm 23:1-3", "Isaiah 26:3", "Romans 15:13", "Psalm 34:8", "John 15:5",
    "Hebrews 4:16", "Psalm 121:1-2", "Matthew 5:14-16", "Isaiah 43:2", "2 Timothy 1:7",
    "Psalm 37:4-5", "John 16:33", "Ephesians 3:20-21", "Nahum 1:7", "1 Corinthians 13:4-7",
    "Psalm 139:13-14", "Romans 10:9", "Isaiah 53:5", "Galatians 5:22-23", "Psalm 103:1-5",
    "Matthew 28:19-20", "Hebrews 12:1-2", "Psalm 51:10-12", "John 10:10", "2 Chronicles 7:14",
    "Philippians 4:6-7", "Psalm 16:11", "1 John 1:9", "Isaiah 55:8-9", "Romans 8:38-39",
    "Psalm 62:1-2", "John 11:25-26", "Proverbs 16:3", "Colossians 3:12-14", "Psalm 145:18",
    "Mark 11:24", "Hebrews 13:5-6", "Exodus 14:14", "1 Thessalonians 5:16-18", "Psalm 118:24",
    "John 1:1-5", "Ephesians 4:32", "Isaiah 40:28-29", "James 1:2-4", "Psalm 32:8",
    "Matthew 6:25-27", "2 Corinthians 12:9", "Psalm 84:11", "Romans 12:1", "Habakkuk 3:17-18",
    "1 Peter 2:9", "Psalm 19:14", "John 13:34-35", "Deuteronomy 6:4-7", "Psalm 90:12",
    "Luke 1:37", "Philippians 1:6", "Psalm 4:8", "2 Corinthians 4:16-18", "Isaiah 9:6",
    "Matthew 7:7-8", "Psalm 100:1-5", "Romans 6:23", "Joshua 24:15", "John 14:27",
    "Psalm 73:26", "Hebrews 10:23", "Ruth 1:16", "Matthew 5:3-6", "Psalm 130:5-6",
    "Titus 3:5", "Isaiah 30:15", "1 Corinthians 10:13", "Psalm 147:3", "Revelation 21:3-4",
    "Proverbs 4:23", "Luke 15:20", "Psalm 42:11", "2 Peter 3:9", "Genesis 50:20",
    "Ecclesiastes 3:1", "John 6:35", "Psalm 56:3-4", "Acts 1:8", "Malachi 3:6",
    "Matthew 22:37-39"
  ]).uniq.freeze

  EPOCH = Date.new(2026, 1, 1)
  # Also skip anything used this recently (covers fall-through when a
  # reference can't be resolved and the next one is taken instead).
  REPEAT_WINDOW = 60
  # A failed or abandoned composition may be retried after this long.
  RETRY_AFTER = 30.minutes
  ARCHIVE_SIZE = 30
  FALLBACK_LINE = "Read it slowly, and let it lead you into prayer.".freeze

  validates :date, :reference, :osis_code, :chapter, :verse_start, :verse_end,
            :translation_code, :verse_text, presence: true

  scope :published, -> { where(date: ..today_date) }
  scope :newest_first, -> { order(date: :desc) }

  class << self
    def today_date = Time.current.in_time_zone(TIME_ZONE).to_date

    # Today's word for a page: ensures the row exists and, when it still lacks
    # a reflection, asks for one in the background. nil only when no Bible
    # text is seeded at all.
    def today
      word = ensure_for(today_date)
      word&.request_composition
      word
    end

    # The row for `date`, created on first use. Two requests racing to create
    # it both end up with the same row: the unique index on `date` turns the
    # loser's INSERT into a lookup (create_or_find_by).
    def ensure_for(date)
      find_by(date:) || begin
        attrs = pick(date)
        attrs && create_or_find_by!(date:) { |word| word.assign_attributes(attrs) }
      end
    end

    # The passage for a date: walk the curated list from the day's position,
    # skipping anything used in the last REPEAT_WINDOW days or not in our DB.
    def pick(date)
      translation = Translation.default
      return nil unless translation

      recent = where(date: (date - REPEAT_WINDOW)...date).pluck(:reference)
      REFERENCES.rotate((date - EPOCH).to_i % REFERENCES.size).each do |ref|
        attrs = resolve(ref, translation)
        return attrs if attrs && recent.exclude?(attrs[:reference])
      end
      nil
    end

    private

    def resolve(reference, translation)
      parsed = ReferenceParser.call(reference)
      return nil unless parsed.valid? && parsed.verse_start

      book = Book.find_by_osis(parsed.osis)
      return nil unless book

      verse_end = parsed.verse_end || parsed.verse_start
      verses = Verse.passage(translation:, book:, chapter: parsed.chapter,
                             verse_start: parsed.verse_start, verse_end:).to_a
      return nil if verses.empty?

      label = "#{book.name} #{parsed.chapter}:#{verses.first.verse_number}"
      label += "-#{verses.last.verse_number}" if verses.size > 1
      {
        reference: label, osis_code: book.osis_code, chapter: parsed.chapter,
        verse_start: verses.first.verse_number, verse_end: verses.last.verse_number,
        translation_code: translation.code, verse_text: verses.map(&:text).join(" ")
      }
    end
  end

  def composed? = reflection.present?

  # Claim the right to compose this word and hand it to a background job. The
  # claim is one atomic UPDATE, so of many simultaneous requests exactly one
  # enqueues — and a failure is retried only after RETRY_AFTER.
  def request_composition
    DailyWordJob.perform_later(id) if claim_composition
  end

  def claim_composition(force: false)
    scope = self.class.where(id:)
    scope = scope.where(reflection: nil).where("ai_attempted_at IS NULL OR ai_attempted_at < ?", RETRY_AFTER.ago) unless force
    scope.update_all(ai_attempted_at: Time.current) == 1
  end

  # Ask the AI for a reflection and prayer and keep them. Never raises; on any
  # failure the word keeps whatever it had (verse alone, or the old text).
  def compose!(composer: DailyWordComposer)
    result = composer.call(self)
    return false unless result.ok?

    update!(reflection: result.reflection, prayer: result.prayer, composed_at: Time.current)
  end

  def book = Book.find_by_osis(osis_code)
  def chapter_label = "#{book&.name || osis_code} #{chapter}"
  def to_param = date.iso8601
  def headline = "#{reference} · Word for #{date.strftime('%A, %-d %B %Y')}"

  def slug
    PassageSlug.slug_for(osis: osis_code, chapter:, verse_start:, verse_end:)
  end

  # Plain-text form for "Copy text" and the share sheet.
  def share_text(url)
    [ "“#{verse_text}”", "— #{reference} (#{translation_code})", reflection, (prayer && "Prayer: #{prayer}"), url ]
      .compact_blank.join("\n\n")
  end
end
