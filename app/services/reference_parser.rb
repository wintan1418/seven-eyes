# Parses human-typed Scripture references into a normalized result.
#
#   ReferenceParser.call("Jn 3:16")      => #<Result John 3:16, valid>
#   ReferenceParser.call("1 Cor 13")     => #<Result 1Cor 13 (whole chapter), valid>
#   ReferenceParser.call("romans 5:1-11")=> #<Result Rom 5:1-11, valid>
#   ReferenceParser.call("nonsense")     => #<Result invalid>
#
# DB-independent on purpose: it resolves the book against Bible::Canon (OSIS codes),
# so it is fully unit-testable without seeded data. Callers turn the OSIS code into a
# Book record when querying verses.
class ReferenceParser
  RANGE_RE = /\A
    (?<book>.*?)\s*
    (?:
      (?<chapter>\d+)
      (?::(?<v1>\d+)(?:\s*[-–—]\s*(?<v2>\d+))?)?
    )?
  \s*\z/x

  Result = Struct.new(:osis, :book_name, :chapter, :verse_start, :verse_end, :valid, keyword_init: true) do
    def valid? = valid
    def whole_chapter? = valid && verse_start.nil?
    def label
      return nil unless valid
      base = "#{book_name} #{chapter}"
      return base if verse_start.nil?
      base += ":#{verse_start}"
      base += "-#{verse_end}" if verse_end && verse_end != verse_start
      base
    end
  end

  def self.call(input) = new(input).call

  def initialize(input)
    @input = input.to_s.strip
  end

  def call
    return invalid if @input.empty?

    work = normalize(@input)
    m = work.match(RANGE_RE)
    return invalid unless m

    osis = resolve_book(m[:book])
    return invalid unless osis

    entry = Bible::Canon.find(osis)
    chapter = resolve_chapter(m[:chapter], entry)
    return invalid unless chapter

    v1 = m[:v1]&.to_i
    v2 = m[:v2]&.to_i
    return invalid if v2 && v1 && v2 < v1

    Result.new(
      osis: osis,
      book_name: entry.name,
      chapter: chapter,
      verse_start: v1,
      verse_end: v2 || v1,
      valid: true
    )
  end

  private

  def invalid = Result.new(valid: false)

  # Lowercase, collapse whitespace, turn leading ordinal words into digits, and
  # tolerate common typos like "jeremiah:3" (colon used as book/chapter separator
  # instead of a space). The chapter:verse colon in "3:16" is unaffected because
  # the character before the colon there is a digit, not a non-digit.
  def normalize(str)
    s = str.downcase.strip
    s = s.sub(/(\D):(\d)/, '\1 \2') # "jeremiah:3" -> "jeremiah 3"
    s = s.gsub(/\s+/, " ")
    s = s.sub(/\A(?:1st|first)\b\.?\s*/, "1 ")
    s = s.sub(/\A(?:2nd|second)\b\.?\s*/, "2 ")
    s = s.sub(/\A(?:3rd|third)\b\.?\s*/, "3 ")
    s
  end

  def resolve_book(token)
    key = Bible::Canon.normalize_key(token)
    return nil if key.empty?
    Bible::Canon.alias_map[key]
  end

  def resolve_chapter(raw, entry)
    if raw.nil?
      # Bare book name: only meaningful for single-chapter books.
      return entry.chapter_count == 1 ? 1 : nil
    end
    n = raw.to_i
    return nil if n < 1 || n > entry.chapter_count
    n
  end
end
