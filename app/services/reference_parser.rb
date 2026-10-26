# Parses human-typed Scripture references into a normalized result.
#
#   ReferenceParser.call("Jn 3:16")        => #<Result John 3:16, valid>
#   ReferenceParser.call("1 Cor 13")       => #<Result 1Cor 13 (whole chapter), valid>
#   ReferenceParser.call("Philippians")    => #<Result Phil 1 (whole chapter), valid>
#   ReferenceParser.call("phillipians 4")  => #<Result Phil 4, valid>      (misspelling)
#   ReferenceParser.call("jude 3")         => #<Result Jude 1:3, valid>    (single-chapter book)
#   ReferenceParser.call("John 99")        => #<Result invalid, error: :bad_chapter, book_name "John">
#   ReferenceParser.call("nonsense")       => #<Result invalid, error: :unknown_book>
#
# This is the heart of every lookup in the app (panes, quick-open, the preach Go
# box, the queue, wiki-links, AI-returned references), so it is deliberately
# forgiving about *how* a reference is typed while staying strict about *what*
# it means: a misspelled book is corrected only when exactly one book is a close
# match, and a chapter outside the book is refused rather than guessed.
#
# DB-independent on purpose: it resolves the book against Bible::Canon (OSIS codes),
# so it is fully unit-testable without seeded data. Callers turn the OSIS code into a
# Book record when querying verses.
class ReferenceParser
  # After normalisation the input is "<book words> [chapter [sep verse [- verse]]]".
  # The book is a lazy run of letters (with an optional 1–3 prefix) so that
  # "1cor1:1", "song of songs 2" and "philippians" all split correctly.
  RANGE_RE = /\A
    (?<book>[1-3]?\s*[a-z][a-z\s]*?)
    (?:\s*
      (?<chapter>\d+)
      (?:
        \s*[:.,]?\s*(?<v1>\d+)(?:\s*-\s*(?<v2>\d+))?   # chapter:verse[-verse]
        |
        \s*-\s*(?<c2>\d+)                              # chapter-chapter (or verses in a one-chapter book)
      )?
    )?
  \s*\z/x

  # Fuzzy matching: a typed book name is corrected to the single closest canonical
  # name when it is within this many edits (longer names may be two letters off).
  FUZZY_MIN_LENGTH = 4
  PREFIX_MIN_LENGTH = 3

  Result = Struct.new(:osis, :book_name, :chapter, :verse_start, :verse_end, :valid, :error, :chapter_count,
                      keyword_init: true) do
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
    return invalid(:blank) if @input.empty?

    work = normalize(@input)
    m = work.match(RANGE_RE)
    return invalid(:unknown_book) unless m

    osis = resolve_book(m[:book])
    return invalid(:unknown_book) unless osis

    entry = Bible::Canon.find(osis)
    chapter, v1, v2 = resolve_location(entry, m[:chapter], m[:v1], m[:v2], m[:c2])
    return invalid(:bad_chapter, entry) unless chapter
    return invalid(:bad_verse, entry) if v1 && v1 < 1

    v1, v2 = v2, v1 if v1 && v2 && v2 < v1 # "3:18-16" is a typo for 3:16-18

    Result.new(
      osis: osis,
      book_name: entry.name,
      chapter: chapter,
      verse_start: v1,
      verse_end: v2 || v1,
      chapter_count: entry.chapter_count,
      valid: true
    )
  end

  private

  def invalid(error, entry = nil)
    Result.new(valid: false, error: error,
               osis: entry&.osis, book_name: entry&.name, chapter_count: entry&.chapter_count)
  end

  # Lowercase, collapse whitespace, and smooth out the many ways people type a
  # reference: ordinal words and Roman numerals before a book ("First John",
  # "II Kings"), "chapter"/"verse" words, dotted abbreviations ("Gen. 1:1"),
  # en/em dashes in ranges, and the "jeremiah:3" colon typo.
  def normalize(str)
    s = str.downcase.strip
    s = s.tr("–—‐‒", "----")      # – — ‐ ‒ → -
    s = s.gsub(/[;!?'"()\[\]]+/, " ")
    s = s.gsub(/\s+/, " ")
    s = s.sub(/\A(?:1st|first)\b\.?\s*/, "1 ")
    s = s.sub(/\A(?:2nd|second)\b\.?\s*/, "2 ")
    s = s.sub(/\A(?:3rd|third)\b\.?\s*/, "3 ")
    s = s.sub(/\A(iii|ii|i)\.?\s+(?=[a-z])/) { { "i" => "1 ", "ii" => "2 ", "iii" => "3 " }[$1] }
    s = s.gsub(/\b(?:chapter|chap|ch)\.?\s*(?=\d)/, " ")                 # "John chapter 3"
    s = s.gsub(/(\d)\s*(?:verses|verse|vv|vs|v)\.?\s*(?=\d)/, '\1:')     # "John 3 v 16"
    s = s.sub(/(\D):(\d)/, '\1 \2')                                       # "jeremiah:3" -> "jeremiah 3"
    s = s.gsub(/([a-z])\./, '\1 ')                                        # "gen. 1:1" -> "gen 1:1"
    s = s.gsub(/[.,:\-\s]+\z/, "")                                        # trailing punctuation
    s.gsub(/\s+/, " ").strip
  end

  # ---- book resolution: exact alias, then unique prefix, then closest spelling ----

  def resolve_book(token)
    key = Bible::Canon.normalize_key(token)
    return nil if key.empty?
    Bible::Canon.alias_map[key] || prefix_match(key) || fuzzy_match(key)
  end

  # "philip" -> Philippians, "gene" -> Genesis. Only when exactly one full book
  # name begins with the typed letters ("thes" is 1 or 2 Thessalonians: refused).
  def prefix_match(key)
    return nil if key.length < PREFIX_MIN_LENGTH
    hits = Bible::Canon.all.select { |b| Bible::Canon.normalize_key(b.name).start_with?(key) }
    hits.size == 1 ? hits.first.osis : nil
  end

  # "phillipians" -> Philippians, "mathew" -> Matthew, "duet" -> Deuteronomy.
  # Measures edit distance against every full name (and, more strictly, every
  # 4+ letter alias) and accepts the single best candidate inside the allowance.
  # A tie between two books means the input is ambiguous, so nothing is guessed.
  def fuzzy_match(key)
    return nil if key.length < FUZZY_MIN_LENGTH
    name_allowance = key.length >= 7 ? 2 : 1

    scored = Bible::Canon.all.map do |b|
      candidates = [ [ Bible::Canon.normalize_key(b.name), name_allowance ] ] +
                   b.aliases.select { |a| a.length >= FUZZY_MIN_LENGTH }.map { |a| [ Bible::Canon.normalize_key(a), 1 ] }
      best = candidates.map { |text, allowance| d = edit_distance(key, text); d <= allowance ? d : nil }.compact.min
      [ b.osis, best ]
    end.reject { |_, d| d.nil? }.sort_by { |_, d| d }

    return nil if scored.empty?
    return nil if scored.size > 1 && scored[0][1] == scored[1][1] # ambiguous
    scored.first.first
  end

  # Damerau–Levenshtein (optimal string alignment): insert, delete, substitute,
  # or swap two adjacent letters each cost one edit.
  def edit_distance(a, b)
    return b.length if a.empty?
    return a.length if b.empty?
    rows = Array.new(a.length + 1) { |i| Array.new(b.length + 1) { |j| i.zero? ? j : (j.zero? ? i : 0) } }
    (1..a.length).each do |i|
      (1..b.length).each do |j|
        cost = a[i - 1] == b[j - 1] ? 0 : 1
        rows[i][j] = [ rows[i - 1][j] + 1, rows[i][j - 1] + 1, rows[i - 1][j - 1] + cost ].min
        if i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]
          rows[i][j] = [ rows[i][j], rows[i - 2][j - 2] + 1 ].min
        end
      end
    end
    rows[a.length][b.length]
  end

  # ---- chapter / verse resolution ----

  # Returns [chapter, verse_start, verse_end], or [nil, ...] when the chapter is
  # outside the book. A bare book name opens chapter 1. In a one-chapter book
  # (Jude, Philemon, Obadiah, 2–3 John) a bare number is a verse: "Jude 3" is
  # Jude 1:3 and "Jude 3-5" is Jude 1:3-5.
  def resolve_location(entry, chapter_raw, v1_raw, v2_raw, c2_raw)
    return [ 1, nil, nil ] if chapter_raw.nil?

    n = chapter_raw.to_i
    v1 = v1_raw&.to_i
    v2 = v2_raw&.to_i

    if entry.chapter_count == 1 && n > 1 && v1.nil?
      return [ 1, n, c2_raw&.to_i ]
    end
    return [ nil, nil, nil ] if n < 1 || n > entry.chapter_count

    # "Psalm 23-24" names two chapters; we show the first. (c2 ignored.)
    [ n, v1, v2 ]
  end
end
