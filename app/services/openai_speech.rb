require "net/http"
require "json"

# Minimal OpenAI text-to-speech client (the /v1/audio/speech endpoint).
# Takes a text chunk (the endpoint caps input at 4096 characters), returns the
# raw mp3 bytes. Chapter-length text is chunked upstream in ChapterNarration.
# Model/voice are configurable via OPENAI_TTS_MODEL / OPENAI_TTS_VOICE.
class OpenaiSpeech
  DEFAULT_MODEL = "tts-1".freeze
  DEFAULT_VOICE = "onyx".freeze # deep and measured — right for Scripture
  DEFAULT_URL   = "https://api.openai.com/v1/audio/speech".freeze
  MAX_INPUT     = 4096

  Result = Struct.new(:ok, :error, :audio, keyword_init: true) do
    def ok? = ok
  end

  def self.configured? = new("").send(:api_key).present?
  def self.voice = ENV["OPENAI_TTS_VOICE"].presence || DEFAULT_VOICE
  def self.synthesize(text) = new(text).synthesize

  def initialize(text)
    @text = text.to_s
  end

  def synthesize
    return Result.new(ok: false, error: :blank) if @text.strip.empty?
    return Result.new(ok: false, error: :no_key) if api_key.blank?

    uri = URI(ENV["OPENAI_TTS_ENDPOINT"].presence || DEFAULT_URL)
    res = post(uri, {
      model: ENV["OPENAI_TTS_MODEL"].presence || DEFAULT_MODEL,
      voice: self.class.voice,
      input: @text[0, MAX_INPUT],
      response_format: "mp3",
      speed: 0.95
    }.to_json)

    unless res.is_a?(Net::HTTPSuccess)
      Rails.logger.warn("[OpenaiSpeech] #{uri.host} -> #{res.code}: #{res.body.to_s.truncate(300)}")
      return Result.new(ok: false, error: :api)
    end
    Result.new(ok: true, audio: res.body.to_s.b)
  rescue => e
    Rails.logger.warn("[OpenaiSpeech] #{e.class}: #{e.message}")
    Result.new(ok: false, error: :api)
  end

  private

  def api_key
    ENV["OPENAI_API_KEY"].presence || ENV["OPENAI_KEY"].presence ||
      Rails.application.credentials.dig(:openai, :api_key)
  end

  def post(uri, json)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 120
    http.open_timeout = 10

    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req["Authorization"] = "Bearer #{api_key}"
    req.body = json
    http.request(req)
  end
end
