require "net/http"
require "json"

# Minimal OpenAI image-generation client (the /v1/images/generations endpoint).
# Chat lives in AiChat; images need a different endpoint and a different response
# shape, so they get their own tiny client. Returns a base64 data: URL ready to
# drop straight into an <img src>, or a Result with an error on any failure.
#
# Model: OPENAI_IMAGE_MODEL if set, otherwise the newest gpt-image model the
# account offers (AiModels asks OpenAI). If OpenAI says the model doesn't exist,
# we look again and retry once, so a retired model can't break illustrations.
# gpt-image models return base64; dall-e-3 returns a temporary URL, which we
# download and encode. Quality (gpt-image only) via OPENAI_IMAGE_QUALITY.
class OpenaiImage
  DEFAULT_MODEL   = "gpt-image-1".freeze
  DEFAULT_URL     = "https://api.openai.com/v1/images/generations".freeze
  DEFAULT_SIZE    = "1024x1024".freeze
  DEFAULT_QUALITY = "medium".freeze
  MAX_PROMPT      = 3800

  Result = Struct.new(:ok, :error, :data_url, keyword_init: true) do
    def ok? = ok
  end

  def self.generate(prompt, size: DEFAULT_SIZE) = new(prompt, size:).generate

  def initialize(prompt, size: DEFAULT_SIZE)
    @prompt = prompt.to_s
    @size = size
  end

  def generate
    return Result.new(ok: false, error: :blank) if @prompt.strip.empty?
    return Result.new(ok: false, error: :no_key) if api_key.blank?
    # Global daily image backstop (AI_DAILY_IMAGE_LIMIT) — images are the
    # priciest call we make.
    return Result.new(ok: false, error: :budget) unless AiBudget.charge(:image)

    b64 = request
    return Result.new(ok: false, error: :api) if b64.blank?
    Result.new(ok: true, data_url: "data:image/png;base64,#{b64}")
  rescue => e
    Rails.logger.warn("[OpenaiImage] #{e.class}: #{e.message}")
    Result.new(ok: false, error: :api)
  end

  private

  def api_key
    ENV["OPENAI_API_KEY"].presence || ENV["OPENAI_KEY"].presence ||
      Rails.application.credentials.dig(:openai, :api_key)
  end

  def model = ENV["OPENAI_IMAGE_MODEL"].presence || AiModels.openai_image(api_key) || DEFAULT_MODEL

  def request(model_name = model, retried: false)
    uri = URI(ENV["OPENAI_IMAGE_ENDPOINT"].presence || DEFAULT_URL)
    # No response_format: the current images endpoint rejects it. gpt-image
    # returns base64; dall-e-3 returns a temporary URL — we handle both below.
    body = { model: model_name, prompt: @prompt[0, MAX_PROMPT], n: 1, size: @size }
    body[:quality] = ENV["OPENAI_IMAGE_QUALITY"].presence || DEFAULT_QUALITY if model_name.start_with?("gpt-image")

    res = post(uri, body.to_json, auth: "Bearer #{api_key}")
    unless res.is_a?(Net::HTTPSuccess)
      Rails.logger.warn("[OpenaiImage] #{uri.host} -> #{res.code} (#{model_name}): #{res.body.to_s.truncate(300)}")
      if !retried && unknown_model?(res)
        AiModels.refresh!(:openai)
        fresh = AiModels.openai_image(api_key, exclude: model_name)
        return request(fresh, retried: true) if fresh && fresh != model_name
      end
      return nil
    end

    datum = JSON.parse(res.body).dig("data", 0) || {}
    return datum["b64_json"] if datum["b64_json"].present?
    fetch_base64(datum["url"]) if datum["url"].present?
  end

  # OpenAI's answer when a model has been retired or never existed.
  def unknown_model?(res)
    res.code.to_i.in?([ 400, 404 ]) && res.body.to_s.match?(/model|does not exist|not found/i) &&
      (JSON.parse(res.body).dig("error", "param") == "model" || res.body.to_s.include?("does not exist"))
  rescue JSON::ParserError
    false
  end

  # dall-e returns a short-lived URL; download it once and base64-encode so the
  # image we hand the page is self-contained and doesn't expire on us.
  def fetch_base64(url)
    res = Net::HTTP.get_response(URI(url))
    return nil unless res.is_a?(Net::HTTPSuccess)
    Base64.strict_encode64(res.body)
  rescue => e
    Rails.logger.warn("[OpenaiImage] fetch #{e.class}: #{e.message}")
    nil
  end

  def post(uri, json, auth:)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 90
    http.open_timeout = 5

    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req["Authorization"] = auth
    req.body = json
    http.request(req)
  end
end
