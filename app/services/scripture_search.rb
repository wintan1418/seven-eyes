# Full-text Bible search the way a KJV Bible app does it ("dew rain" lists the
# verses holding both words, words marked). One translation, optionally one
# testament or one book. Results come in tiers, then in Bible order:
#
#   1. phrase  — the words side by side, as typed ("the dew of heaven")
#   2. all     — every word somewhere in the verse
#   3. partial — some of the words (more of them first)
#
# Words are matched by their English stem (Postgres' text_vector), so "rain"
# also finds "rained". Stop words ("the", "of") don't count. Bible order inside
# a tier keeps the list the same on every run.
#
#   result = ScriptureSearch.call("dew rain", translation: kjv, scope: "ot")
#   result.hits.first.verse  # => Deuteronomy 32:2
#   result.hits.first.tier   # => :all
#   result.all_count         # => verses containing every word
#   ScriptureSearch.highlight(text, result.query_tsquery) — see #highlighted
#
# The device has the same ranking for downloaded Bibles: lib/scripture_search.js.
class ScriptureSearch
  LIMIT = 250
  MARK_OPEN = "⟦".freeze  # ⟦ — never in Scripture text; swapped for <mark>
  MARK_CLOSE = "⟧".freeze # ⟧
  SCOPES = %w[ all ot nt ].freeze

  Hit = Struct.new(:verse, :tier, :matched, :marked, keyword_init: true) do
    # The verse text, HTML-escaped, with the matched words in <mark>.
    def highlighted
      ERB::Util.html_escape(marked.presence || verse.text)
               .gsub(MARK_OPEN, "<mark>").gsub(MARK_CLOSE, "</mark>").html_safe
    end

    def reference = "#{verse.book.name} #{verse.chapter}:#{verse.verse_number}"
  end

  Result = Struct.new(:query, :words, :terms, :hits, :all_count, :any_count, :phrase_count, :scope, keyword_init: true) do
    def blank? = words.empty?
    def any? = hits.any?
    def empty? = hits.empty?
    def truncated? = any_count > hits.size
    def all_hits = hits.select { |h| h.tier != :partial }
    def partial_hits = hits.select { |h| h.tier == :partial }

    # "dew and rain" — the words as typed (stop words left out).
    def terms_label = terms.to_sentence(two_words_connector: " and ", last_word_connector: " and ")
  end

  def self.call(...) = new(...).call

  def initialize(query, translation:, scope: nil, limit: LIMIT)
    @query = query.to_s.squish.first(200)
    @translation = translation
    @scope = scope.to_s.presence || "all"
    @limit = limit
  end

  def call
    words = lexemes
    return empty_result(words) if words.empty? || @translation.nil?

    rel = scoped(Verse.where(translation: @translation).joins(:book))
    any_q = any_tsquery(words)
    rel = rel.where("verses.text_vector @@ #{any_q}")

    hits_sql = words.map { |w| "(verses.text_vector @@ #{quote_tsquery(w)})::int" }.join(" + ")
    phrase_sql = words.size > 1 ? "(verses.text_vector @@ phraseto_tsquery('english', #{quote(@query)}))" : "false"

    counts = rel.pick(Arel.sql(
      "count(*), count(*) FILTER (WHERE #{hits_sql} = #{words.size}), count(*) FILTER (WHERE #{phrase_sql})"
    ))

    rows = rel.includes(:book)
              .select("verses.*",
                      "#{phrase_sql} AS phrase_hit",
                      "#{hits_sql} AS words_hit",
                      "ts_headline('english', verses.text, #{any_q}, " \
                      "'HighlightAll=true, StartSel=#{MARK_OPEN}, StopSel=#{MARK_CLOSE}') AS marked_text")
              .reorder(Arel.sql("phrase_hit DESC, words_hit DESC, books.position, verses.chapter, verses.verse_number"))
              .limit(@limit)
              .to_a

    hits = rows.map do |v|
      tier = if v.phrase_hit then :phrase
      elsif v.words_hit.to_i >= words.size then :all
      else :partial
      end
      Hit.new(verse: v, tier:, matched: v.words_hit.to_i, marked: v.marked_text)
    end

    Result.new(query: @query, words:, terms: typed_terms, hits:, any_count: counts[0].to_i, all_count: counts[1].to_i,
               phrase_count: counts[2].to_i, scope: @scope)
  end

  private

  def empty_result(words)
    Result.new(query: @query, words:, terms: typed_terms, hits: [], all_count: 0, any_count: 0, phrase_count: 0, scope: @scope)
  end

  # The query's stems as Postgres sees them, in typed order, stop words out.
  def lexemes
    return [] if @query.blank?
    sql = ActiveRecord::Base.sanitize_sql_array([
      "SELECT lexeme FROM unnest(to_tsvector('english', ?)) ORDER BY positions[1]", @query
    ])
    ActiveRecord::Base.connection.select_values(sql).uniq.first(12)
  end

  # The typed words that count (not stop words), lower-case, once each.
  def typed_terms
    words = @query.downcase.scan(/[\p{L}'’]+/).uniq.first(12)
    return [] if words.empty?
    sql = ActiveRecord::Base.sanitize_sql_array([
      "SELECT w FROM unnest(ARRAY[?]::text[]) WITH ORDINALITY AS t(w, i) " \
      "WHERE length(to_tsvector('english', w)::text) > 0 ORDER BY i", words
    ])
    ActiveRecord::Base.connection.select_values(sql)
  end

  def scoped(rel)
    case @scope
    when "ot" then rel.where(books: { testament: Book.testaments[:old] })
    when "nt" then rel.where(books: { testament: Book.testaments[:new] })
    when "all" then rel
    else
      book = Book.find_by_osis(@scope)
      book ? rel.where(book_id: book.id) : rel
    end
  end

  def any_tsquery(words)
    "(#{words.map { |w| quote_tsquery(w) }.join(' || ')})"
  end

  # A single lexeme as a tsquery, taken literally (it is already a stem).
  def quote_tsquery(word)
    "#{quote("'#{word.gsub("'", "''")}'")}::tsquery"
  end

  def quote(str) = ActiveRecord::Base.connection.quote(str)
end
