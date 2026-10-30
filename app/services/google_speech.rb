require "net/http"
require "json"
require "base64"

# Google Cloud Text-to-Speech (REST, API-key auth). Used before OpenAI because
# Google gives a free allowance every month (about 1M characters for Neural2
# voices). We count characters ourselves and stop at GOOGLE_TTS_MONTHLY_CHARS
# (default 900k) so the free allowance is never exceeded; past it, narration
# falls through to the next voice in line.
#
# Key: GOOGLE_TTS_API_KEY (or credentials google.tts_api_key). Restrict the key
# to the Text-to-Speech API in the Google Cloud console.
class GoogleSpeech
  URL = "https://texttospeech.googleapis.com/v1/text:synthesize".freeze
  MAX_INPUT = 4800 # the API caps input at 5000 bytes
  DEFAULT_MONTHLY_CHARS = 900_000

  Result = OpenaiSpeech::Result

  def self.configured? = api_key.present?
  def self.api_key = ENV["GOOGLE_TTS_API_KEY"].presence || Rails.application.credentials.dig(:google, :tts_api_key)
  def self.monthly_limit = (ENV["GOOGLE_TTS_MONTHLY_CHARS"].presence || DEFAULT_MONTHLY_CHARS).to_i
  def self.used_this_month = Rails.cache.read(counter_key, raw: true).to_i
  def self.within_free_allowance?(chars = 0) = used_this_month + chars <= monthly_limit
  def self.counter_key = "google_tts/chars/#{Time.now.utc.strftime('%Y-%m')}"

  # Characters a chapter would use, so we can check before starting it.
  def self.charge(chars)
    Rails.cache.increment(counter_key, chars, expires_in: 40.days)
  rescue => e
    Rails.logger.warn("[GoogleSpeech] counter: #{e.class}: #{e.message}")
  end

  def self.synthesize(text, voice:, language:) = new(text, voice:, language:).synthesize

  def initialize(text, voice:, language:)
    @text = text.to_s
    @voice = voice
    @language = language
  end

  def synthesize
    return Result.new(ok: false, error: :blank) if @text.strip.empty?
    return Result.new(ok: false, error: :no_key) unless self.class.configured?
    return Result.new(ok: false, error: :free_allowance) unless self.class.within_free_allowance?(@text.bytesize)

    res = post({
      input: { text: @text.byteslice(0, MAX_INPUT).scrub("") },
      voice: { languageCode: @language, name: @voice },
      audioConfig: { audioEncoding: "MP3", speakingRate: 0.95 }
    }.to_json)

    unless res.is_a?(Net::HTTPSuccess)
      Rails.logger.warn("[GoogleSpeech] -> #{res.code}: #{res.body.to_s.truncate(300)}")
      return Result.new(ok: false, error: :api)
    end
    self.class.charge(@text.bytesize)
    Result.new(ok: true, audio: Base64.decode64(JSON.parse(res.body)["audioContent"].to_s).b)
  rescue => e
    Rails.logger.warn("[GoogleSpeech] #{e.class}: #{e.message}")
    Result.new(ok: false, error: :api)
  end

  private

  def post(json)
    uri = URI(URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 120
    http.open_timeout = 5
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req["X-Goog-Api-Key"] = self.class.api_key
    req.body = json
    http.request(req)
  end
end
