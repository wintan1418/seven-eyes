require "net/http"
require "json"

# A tiny multi-provider chat completion client with automatic fail-over.
#
#   AiChat.call(system: "...", user: "...", json: true)
#   => #<Result ok=true content="{...}" provider=:gemini>
#
# Providers are tried in priority order; the first one that is *configured*
# (has a key) and *succeeds* wins. If it errors (bad key, timeout, non-2xx),
# the next configured provider is tried automatically. This lets the app run on
# Gemini today and silently gain Abacus RouteLLM fail-over the moment its key is
# added to the environment — no code change.
#
# Supported providers and their env keys:
#   :gemini   — Google Generative Language API   (Google_GEMINI_API_KEY / GEMINI_API_KEY)
#   :routellm — Abacus.AI RouteLLM (OpenAI-shape) (ROUTELLM_API_KEY / ABACUS_API_KEY)
#
# Kept network-shaped exactly like ScriptureSuggester so it's unit-testable via
# subclassing/overriding the per-provider request seams.
class AiChat
  GEMINI_DEFAULT_MODEL   = "gemini-2.0-flash".freeze
  ROUTELLM_DEFAULT_MODEL = "route-llm".freeze
  ROUTELLM_DEFAULT_URL   = "https://routellm.abacus.ai/v1/chat/completions".freeze

  # Order = priority. A provider is skipped if it has no key.
  PROVIDERS = %i[ gemini routellm ].freeze

  Result = Struct.new(:ok, :content, :provider, :error, keyword_init: true) do
    def ok? = ok
  end

  def self.call(system:, user:, json: true, temperature: 0.2)
    new(system:, user:, json:, temperature:).call
  end

  def initialize(system:, user:, json: true, temperature: 0.2)
    @system = system.to_s
    @user = user.to_s
    @json = json
    @temperature = temperature
  end

  def call
    configured = PROVIDERS.select { |p| key_for(p).present? }
    return Result.new(ok: false, error: :no_key) if configured.empty?

    last_error = :api
    configured.each do |provider|
      content = dispatch(provider)
      return Result.new(ok: true, content: content, provider: provider) if content.present?
    rescue => e
      Rails.logger.warn("[AiChat] #{provider} failed: #{e.class}: #{e.message}")
      last_error = :api
      next
    end
    Result.new(ok: false, error: last_error)
  end

  private

  def dispatch(provider)
    case provider
    when :gemini   then gemini_request
    when :routellm then routellm_request
    end
  end

  # ---- keys (overridable seams in tests) ----

  def key_for(provider)
    case provider
    when :gemini
      ENV["Google_GEMINI_API_KEY"].presence || ENV["GEMINI_API_KEY"].presence ||
        ENV["GOOGLE_GEMINI_API_KEY"].presence ||
        Rails.application.credentials.dig(:gemini, :api_key)
    when :routellm
      ENV["ROUTELLM_API_KEY"].presence || ENV["Route_LLM_API_KEY"].presence ||
        ENV["ABACUS_ROUTELLM_API_KEY"].presence || ENV["ABACUS_API_KEY"].presence ||
        Rails.application.credentials.dig(:routellm, :api_key)
    end
  end

  # ---- Gemini (Google Generative Language API) ----

  def gemini_request
    model = ENV["GEMINI_MODEL"].presence || GEMINI_DEFAULT_MODEL
    uri = URI("https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent")

    body = {
      system_instruction: { parts: [ { text: @system } ] },
      contents: [ { role: "user", parts: [ { text: @user } ] } ],
      generationConfig: { temperature: @temperature }
    }
    body[:generationConfig][:responseMimeType] = "application/json" if @json

    key = key_for(:gemini)
    # Gemini accepts an AI Studio API key (via the x-goog-api-key header) OR an
    # OAuth access token (via Authorization: Bearer). We can't always tell which
    # a key is from its shape, so try the header key first, then Bearer.
    appliers = [
      ->(req) { req["x-goog-api-key"] = key },
      ->(req) { req["Authorization"] = "Bearer #{key}" }
    ]

    appliers.each do |apply_auth|
      res = post_json(uri, body, &apply_auth)
      return JSON.parse(res).dig("candidates", 0, "content", "parts", 0, "text") if res
    end
    nil
  end

  # ---- Abacus RouteLLM (OpenAI-compatible /chat/completions) ----

  def routellm_request
    uri = URI(ENV["ROUTELLM_ENDPOINT"].presence || ROUTELLM_DEFAULT_URL)
    model = ENV["ROUTELLM_MODEL"].presence || ROUTELLM_DEFAULT_MODEL

    body = {
      model: model,
      temperature: @temperature,
      messages: [
        { role: "system", content: @system },
        { role: "user", content: @user }
      ]
    }
    body[:response_format] = { type: "json_object" } if @json

    res = post_json(uri, body) { |req| req["Authorization"] = "Bearer #{key_for(:routellm)}" }
    return nil unless res

    JSON.parse(res).dig("choices", 0, "message", "content")
  end

  # ---- shared HTTP (returns the raw response body String, or nil on non-2xx) ----

  def post_json(uri, body)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 40
    http.open_timeout = 10

    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    yield req if block_given?
    req.body = body.to_json

    res = http.request(req)
    unless res.is_a?(Net::HTTPSuccess)
      Rails.logger.warn("[AiChat] #{uri.host} -> #{res.code}: #{res.body.to_s.truncate(300)}")
      return nil
    end
    res.body
  end
end
