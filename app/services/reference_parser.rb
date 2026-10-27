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
  # After normalisation the input is
  #   "<book words> [chapter [sep verse [- [chapter sep] verse]] | [- chapter]]".
  # The book is a lazy run of letters (with an optional 1–3 prefix) so that
  # "1cor1:1", "song of songs 2" and "philippians" all split correctly.
  RANGE_RE = /\A
    (?<book>[1-3]?\s*[a-z][a-z\s]*?)
    (?:\s*
      (?<chapter>\d+)
      (?:
        \s*[:.,]?\s*(?<v1>\d+)                                     # chapter:verse
          (?:\s*-\s*(?:(?<c2v>\d+)\s*[:.]\s*)?(?<v2>\d+))?        #   [-verse | -chapter:verse]
        |
        \s*-\s*(?<c2>\d+)                                          # chapter-chapter (or verses in a one-chapter book)
      )?
    )?
  \s*\z/x

  # Fuzzy matching: a typed book name is corrected to the single closest canonical
  # name when it is within this many edits (longer names may be two letters off).
  FUZZY_MIN_LENGTH = 4
  PREFIX_MIN_LENGTH = 3

  # chapter_end equals chapter for a single-chapter reference; verse_end is the
  # last verse *in chapter_end* ("John 3:16-4:2" => chapter 3, verse_start 16,
  # chapter_end 4, verse_end 2). "Matt 5-7" has chapters 5..7 and no verses.
  # open_ended ("John 3:16ff") runs from verse_start to the end of the chapter,
  # so verse_end is nil.
  Result = Struct.new(:osis, :book_name, :chapter, :verse_start, :verse_end, :valid, :error, :chapter_count,
                      :chapter_end, :open_ended, keyword_init: true) do
    def valid? = valid
    def whole_chapter? = valid && verse_start.nil?
    def multi_chapter? = valid && chapter_end.to_i > chapter.to_i
    def open_ended? = valid && open_ended == true
    def last_chapter = chapter_end || chapter

    def label
      return nil unless valid
      base = "#{book_name} #{chapter}"
      if verse_start.nil?
        return multi_chapter? ? "#{base}-#{chapter_end}" : base
      end
      base += ":#{verse_start}"
      return "#{base}ff" if open_ended?
      if multi_chapter?
        base += "-#{chapter_end}:#{verse_end}"
      elsif verse_end && verse_end != verse_start
        base += "-#{verse_end}"
      end
      base
    end

    # Keyword arguments for Verse.passage that load exactly this reference.
    def passage_args
      {
        chapter: chapter, chapter_end: chapter_end, verse_start: verse_start,
        verse_end: open_ended? ? Float::INFINITY : verse_end
      }
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
    location = resolve_location(entry, m)
    return invalid(location, entry) if location.is_a?(Symbol)

    chapter, v1, chapter_end, v2 = location
    open_ended = @open_ended && v1 && v2.nil? ? true : false

    Result.new(
      osis: osis,
      book_name: entry.name,
      chapter: chapter,
      chapter_end: chapter_end,
      verse_start: v1,
      verse_end: open_ended ? nil : (v2 || v1),
      open_ended: open_ended,
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
    s = s.sub(/\A(?:saint|st)\b\.?\s*(?=[a-z])/, "")                    # "St John 3:16"
    s = s.sub(/\A(?:1st|first)\b\.?\s*/, "1 ")
    s = s.sub(/\A(?:2nd|second)\b\.?\s*/, "2 ")
    s = s.sub(/\A(?:3rd|third)\b\.?\s*/, "3 ")
    s = s.sub(/\A(iii|ii|i)\.?\s+(?=[a-z])/) { { "i" => "1 ", "ii" => "2 ", "iii" => "3 " }[$1] }
    s = s.gsub(/\b(?:chapter|chap|ch)\.?\s*(?=\d)/, " ")                 # "John chapter 3"
    s = s.gsub(/(\d)\s*(?:verses|verse|vv|vs|v)\.?\s*(?=\d)/, '\1:')     # "John 3 v 16"
    s = s.sub(/(\D):(\d)/, '\1 \2')                                       # "jeremiah:3" -> "jeremiah 3"
    s = s.gsub(/([a-z])\./, '\1 ')                                        # "gen. 1:1" -> "gen 1:1"
    s = s.gsub(/[.,:\-\s]+\z/, "")                                        # trailing punctuation
    @open_ended = false
    s = s.sub(/(\d)\s*ff?\z/) { @open_ended = true; $1 }                 # "3:16ff" -> through chapter end
    s = s.gsub(/(?<=\d)[abc](?=\s*-|\s*\z)/, "")                          # "3:16a", "3:16b-18" (verse parts)
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

  # Returns [chapter, verse_start, chapter_end, verse_end], or an error symbol
  # (:bad_chapter / :bad_verse). A bare book name opens chapter 1. In a
  # one-chapter book (Jude, Philemon, Obadiah, 2–3 John) bare numbers are
  # verses: "Jude 3" is Jude 1:3 and "Jude 1-3" is Jude 1:1-3.
  def resolve_location(entry, m)
    return [ 1, nil, 1, nil ] if m[:chapter].nil?

    n = m[:chapter].to_i
    v1 = m[:v1]&.to_i
    v2 = m[:v2]&.to_i
    c2 = m[:c2]&.to_i
    c2v = m[:c2v]&.to_i

    if entry.chapter_count == 1 && v1.nil? && (n > 1 || c2)
      v1, v2 = n, c2
      return :bad_verse if v1 < 1 || (v2 && v2 < 1)
      v1, v2 = v2, v1 if v2 && v2 < v1
      return [ 1, v1, 1, v2 ]
    end
    return :bad_chapter if n < 1 || n > entry.chapter_count
    return :bad_verse if (v1 && v1 < 1) || (v2 && v2 < 1)

    if c2 # "Matt 5-7": a run of whole chapters
      first, last = [ n, c2 ].minmax
      return :bad_chapter if first < 1 || last > entry.chapter_count
      return [ first, nil, last, nil ]
    end

    if c2v && c2v != n # "John 3:16-4:2": crosses a chapter boundary
      return :bad_chapter if c2v < n || c2v > entry.chapter_count
      return [ n, v1, c2v, v2 ]
    end

    v1, v2 = v2, v1 if v1 && v2 && v2 < v1 # "3:18-16" is a typo for 3:16-18
    [ n, v1, n, v2 ]
  end
end
