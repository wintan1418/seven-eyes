require "net/http"
require "json"
require "set"

# Turns a free-text description / half-remembered idea into relevant Scripture
# references using an LLM, then validates each through ReferenceParser and loads a
# preview from our own DB. The LLM only ever returns *references* — never verse text —
# so the displayed words always come from our vetted public-domain translations.
class ScriptureSuggester
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze
  MODEL = "gpt-4o-mini".freeze
  MAX = 8

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are a Bible reference finder. Given a description, theme, or half-remembered
    idea, return the most relevant Bible passages. Respond ONLY as JSON of the form:
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
    return Result.new(ok: false, error: :no_key) if api_key.blank?

    refs = request_references
    return Result.new(ok: false, error: :api) if refs.nil?

    Result.new(ok: true, suggestions: build_suggestions(refs))
  rescue => e
    Rails.logger.error("[ScriptureSuggester] #{e.class}: #{e.message}")
    Result.new(ok: false, error: :api)
  end

  private

  def api_key
    @api_key ||= ENV["OPENAI_API_KEY"].presence ||
                 Rails.application.credentials.dig(:openai, :api_key)
  end

  def request_references
    uri = URI(ENDPOINT)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 30
    http.open_timeout = 10

    req = Net::HTTP::Post.new(uri)
    req["Authorization"] = "Bearer #{api_key}"
    req["Content-Type"] = "application/json"
    req.body = {
      model: MODEL,
      temperature: 0.2,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: @query }
      ]
    }.to_json

    res = http.request(req)
    return nil unless res.is_a?(Net::HTTPSuccess)

    content = JSON.parse(res.body).dig("choices", 0, "message", "content")
    extract_references(content)
  end

  def extract_references(content)
    return [] if content.blank?
    Array(JSON.parse(content)["references"]).first(MAX)
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
