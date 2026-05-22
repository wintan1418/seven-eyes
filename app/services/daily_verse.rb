# Picks a "verse of the day" deterministically from a small curated list of
# beloved, single-verse references. The same date always yields the same verse,
# and it rotates daily. Resolves the reference against a seeded translation
# (KJV preferred) so the words always come from our own DB — never hardcoded.
class DailyVerse
  REFERENCES = [
    "John 3:16", "Psalm 23:1", "Proverbs 3:5", "Isaiah 40:31", "Romans 8:28",
    "Philippians 4:13", "Joshua 1:9", "Jeremiah 29:11", "Matthew 11:28",
    "Psalm 46:10", "Romans 12:2", "2 Corinthians 5:17", "Galatians 2:20",
    "Ephesians 2:8", "Hebrews 11:1", "James 1:5", "1 John 4:19", "Psalm 119:105",
    "Matthew 6:33", "Lamentations 3:22", "Micah 6:8", "Zephaniah 3:17",
    "Psalm 27:1", "Isaiah 41:10", "John 14:6", "Romans 5:8", "Psalm 91:1",
    "Colossians 3:23", "1 Peter 5:7", "Deuteronomy 31:6"
  ].freeze

  Result = Struct.new(:text, :reference_label, :translation_code, keyword_init: true)

  def self.for(date: Date.current)
    new(date).call
  end

  def initialize(date)
    @date = date
  end

  def call
    translation = Translation.find_by(code: "KJV") || Translation.first
    return nil unless translation

    REFERENCES.rotate(@date.yday).each do |ref|
      result = lookup(ref, translation)
      return result if result
    end
    nil
  end

  private

  def lookup(reference, translation)
    parsed = ReferenceParser.call(reference)
    return nil unless parsed.valid? && parsed.verse_start

    book = Book.find_by_osis(parsed.osis)
    return nil unless book

    verse = Verse.find_by(translation:, book:, chapter: parsed.chapter, verse_number: parsed.verse_start)
    return nil unless verse

    Result.new(text: verse.text, reference_label: verse.label, translation_code: translation.code)
  end
end
