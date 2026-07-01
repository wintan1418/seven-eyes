require "json"
require "set"

# The preach-mode quick search. The preacher mentions *anything* — a Bible
# story, a person, a movement, church history ("the Azusa Street revival",
# "the crusaders"), a place — and the projection volunteer types it in.
# The AI answers like a study assistant: a short, projectable explanation
# (the "card") plus related Scripture references.
#
# The references are re-validated through ReferenceParser and previewed from
# our own DB — the projected *verse text* always comes from our vetted
# public-domain translations. Only the explanation card is LLM prose, and it
# is clearly the volunteer's choice to project it.
class PulpitSearch
  MAX_REFS = 6
  SUMMARY_LIMIT = 460

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are a study assistant at a preacher's side during a sermon. The operator
    types something the preacher just mentioned: a Bible passage they can't place,
    a person, a place, an object, a theme, a single word, an event, or a movement
    from church history. Queries are often terse — one or two words ("dragon",
    "leviathan", "manna", "grace", "azusa street"). Treat a bare word as "where
    does this appear in Scripture?" and answer it.

    Respond ONLY as minified JSON with exactly these keys:
    {"topic": "The Dragon in Scripture",
     "summary": "2-4 short factual sentences, suitable to project on a church screen.",
     "references": ["Revelation 12:3-9", "Job 41:1", "Psalm 74:13-14"]}

    Rules:
    - "topic": a short display title (max 8 words).
    - "summary": plain reverent prose, max 420 characters, no markdown. Describe how
      the word/person/theme appears in the Bible. Only leave it "" if the query is
      truly not a biblical or church-history subject at all. Do not fabricate
      historical dates or events you are unsure of — but biblical themes are safe.
    - "references": ALWAYS return the Bible passages where this word/person/theme/
      event genuinely appears — up to 6 (standard English book names, chapter:verse,
      ranges allowed). Only return an empty array if the query has no place in
      Scripture whatsoever. Nearly every biblical word has at least one passage;
      find it. References only — never include verse text.

    Examples: "dragon" -> Revelation 12:3-9, Revelation 20:2, Job 41:1.
    "leviathan" -> Job 41:1, Psalm 74:14, Isaiah 27:1. "manna" -> Exodus 16:4,
    John 6:31-35. Give this level of coverage for any biblical word.
  PROMPT

  Result = Struct.new(:ok, :error, :topic, :summary, :suggestions, keyword_init: true) do
    def ok? = ok
  end

  Suggestion = Struct.new(:reference, :osis, :chapter, :verse_start, :verse_end, :preview, keyword_init: true)

  def self.call(query, translation: nil) = new(query, translation:).call

  def initialize(query, translation: nil)
    @query = query.to_s.strip
    @translation = translation
  end

  def call
    return Result.new(ok: false, error: :blank) if @query.empty?

    res = chat_completion
    return Result.new(ok: false, error: res.error || :api) unless res.ok?

    data = parse(res.content)
    return Result.new(ok: false, error: :api) if data.nil?

    suggestions = build_suggestions(Array(data["references"]).first(MAX_REFS))
    summary = data["summary"].to_s.strip.truncate(SUMMARY_LIMIT)
    return Result.new(ok: false, error: :nothing) if summary.blank? && suggestions.empty?

    Result.new(ok: true, topic: data["topic"].to_s.strip.presence || @query.titleize,
               summary: summary, suggestions: suggestions)
  rescue => e
    Rails.logger.error("[PulpitSearch] #{e.class}: #{e.message}")
    Result.new(ok: false, error: :api)
  end

  private

  # Network seam — overridden in tests to avoid a live API call.
  def chat_completion
    AiChat.call(system: SYSTEM_PROMPT, user: @query, json: true)
  end

  def parse(content)
    return nil if content.blank?
    cleaned = content.to_s.strip.sub(/\A```(?:json)?\s*/, "").sub(/```\z/, "")
    JSON.parse(cleaned)
  rescue JSON::ParserError
    nil
  end

  def build_suggestions(refs)
    translation = @translation || Translation.find_by(code: "KJV") || Translation.first
    seen = Set.new

    refs.filter_map do |raw|
      parsed = ReferenceParser.call(raw)
      next unless parsed.valid?

      key = [ parsed.osis, parsed.chapter, parsed.verse_start ]
      next if seen.include?(key)
      seen << key

      book = Book.find_by_osis(parsed.osis)
      next unless book

      verse = parsed.verse_start || 1
      preview = Verse.passage(translation:, book:, chapter: parsed.chapter,
                              verse_start: verse, verse_end: verse).first

      Suggestion.new(
        reference: parsed.label, osis: parsed.osis, chapter: parsed.chapter,
        verse_start: parsed.verse_start, verse_end: parsed.verse_end,
        preview: preview&.text
      )
    end
  end
end
