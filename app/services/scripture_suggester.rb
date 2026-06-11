require "json"
require "set"

# Turns a free-text description / half-remembered idea into relevant Scripture
# references using an LLM, then validates each through ReferenceParser and loads a
# preview from our own DB. The LLM only ever returns *references* — never verse text —
# so the displayed words always come from our vetted public-domain translations.
#
# LLM calls go through AiChat (Gemini first, Abacus RouteLLM fail-over).
class ScriptureSuggester
  MAX = 8

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are a Bible reference finder. Given a description, theme, half-remembered
    idea, or historical event, return the most relevant Bible passages. Respond ONLY
    as JSON of the form:
    {"references": ["Romans 5:1", "Ephesians 2:8-9", "John 3:16"]}
    Rules: use standard English book names with chapter:verse (ranges allowed); at most
    8 references; order by relevance; return ONLY references, no commentary or verse text.
  PROMPT

  Result = Struct.new(:ok, :error, :suggestions, keyword_init: true) do
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

    Result.new(ok: true, suggestions: build_suggestions(extract_references(res.content)))
  rescue => e
    Rails.logger.error("[ScriptureSuggester] #{e.class}: #{e.message}")
    Result.new(ok: false, error: :api)
  end

  private

  # Network seam — overridden in tests to avoid a live API call.
  def chat_completion
    AiChat.call(system: SYSTEM_PROMPT, user: @query, json: true)
  end

  def extract_references(content)
    return [] if content.blank?
    cleaned = content.to_s.strip.sub(/\A```(?:json)?\s*/, "").sub(/```\z/, "")
    Array(JSON.parse(cleaned)["references"]).first(MAX)
  rescue JSON::ParserError
    []
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
