# Every voice the Audio Bible can read with, and the order we try them in.
#
#   Auto (default): a real person reading the KJV (public-domain recording)
#   when the chapter has one, then Google (free monthly allowance), then
#   OpenAI (paid), then the phone's own voice on the device.
#
# A listener can pick one voice instead; if it can't play a chapter (not
# configured, KJV-only, out of allowance, or it failed), the rest of the Auto
# order follows so the button always speaks.
#
# `id` is what ChapterAudio#voice stores. OpenAI voices keep their bare names
# ("onyx") so audio recorded before voices existed keeps working.
module AudioVoices
  Voice = Data.define(:id, :provider, :name, :detail, :provider_voice, :language) do
    def paid? = provider == :openai
    def free? = !paid?
    def server? = provider != :device
  end

  AUTO = "auto".freeze

  HUMAN = Voice.new(id: "human", provider: :recording, name: "Human reader",
                    detail: "A real person reading the King James Version", provider_voice: nil, language: "en")

  GOOGLE = [
    Voice.new(id: "google:en-GB-Neural2-B", provider: :google, name: "Thomas",
              detail: "British, calm and deep", provider_voice: "en-GB-Neural2-B", language: "en-GB"),
    Voice.new(id: "google:en-US-Neural2-J", provider: :google, name: "James",
              detail: "American, warm", provider_voice: "en-US-Neural2-J", language: "en-US"),
    Voice.new(id: "google:en-GB-Neural2-C", provider: :google, name: "Grace",
              detail: "British, gentle", provider_voice: "en-GB-Neural2-C", language: "en-GB"),
    Voice.new(id: "google:en-US-Neural2-F", provider: :google, name: "Ruth",
              detail: "American, bright", provider_voice: "en-US-Neural2-F", language: "en-US")
  ].freeze

  OPENAI = [
    Voice.new(id: "onyx", provider: :openai, name: "Onyx", detail: "Deep and measured",
              provider_voice: "onyx", language: "en"),
    Voice.new(id: "fable", provider: :openai, name: "Fable", detail: "British storyteller",
              provider_voice: "fable", language: "en"),
    Voice.new(id: "nova", provider: :openai, name: "Nova", detail: "Clear and warm",
              provider_voice: "nova", language: "en"),
    Voice.new(id: "shimmer", provider: :openai, name: "Shimmer", detail: "Soft and calm",
              provider_voice: "shimmer", language: "en")
  ].freeze

  DEVICE = Voice.new(id: "device", provider: :device, name: "Phone voice",
                     detail: "Free, works offline, sounds robotic", provider_voice: nil, language: nil)

  ALL = ([ HUMAN ] + GOOGLE + OPENAI + [ DEVICE ]).freeze

  module_function

  def find(id) = ALL.find { |v| v.id == id.to_s }

  def default_google = find("google:#{ENV['GOOGLE_TTS_VOICE'].presence || 'en-GB-Neural2-B'}") || GOOGLE.first
  def default_openai = find(OpenaiSpeech.voice) || OPENAI.first

  # Voices this server can use right now (for the chooser).
  def selectable
    voices = [ HUMAN ]
    voices += GOOGLE if GoogleSpeech.configured?
    voices += OPENAI if OpenaiSpeech.configured?
    voices + [ DEVICE ]
  end

  # Server voices to try for this chapter, best first. Empty means "use the
  # phone's voice" (the client falls back to it).
  def chain(preferred, translation:, book:, chapter:)
    auto = [ HUMAN, default_google, default_openai ]
    picked = find(preferred)
    return [] if picked == DEVICE

    order = picked ? [ picked ] + auto : auto
    order.uniq.select { |v| usable?(v, translation:, book:, chapter:) }
  end

  def usable?(voice, translation:, book:, chapter:)
    case voice.provider
    when :recording then translation.code == "KJV" && KjvRecording.covers?(book, chapter)
    when :google then GoogleSpeech.configured? && GoogleSpeech.within_free_allowance?
    when :openai then OpenaiSpeech.configured?
    else false
    end
  end
end
