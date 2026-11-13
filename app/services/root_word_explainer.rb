require "json"
require "digest"

# "Ask Rabbi" on a root-word card: one or two plain sentences a preacher can
# put on the screen under the original word — what it meant to the first
# hearers and why it matters in THIS verse. Grounded in the Strong's entry and
# the verse (both from our DB); the model only phrases it. Cached per word +
# verse, so a second church projecting agapē in John 3:16 costs nothing.
# The slide works without it; the operator sees and can edit it first.
class RootWordExplainer
  CACHE_TTL = 30.days
  MAX_TOKENS = 400
  LIMIT = 320 # chars kept

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You help a preacher explain one Hebrew or Greek word to a congregation, live,
    on a projector slide. You are given the verse, the English word, and the
    Strong's lexicon entry for the original word.

    Write ONE or TWO short sentences (at most 40 words in all), warm and clear,
    that a congregation can read in a few seconds:
    - what the original word means, in plain English;
    - what that adds to THIS verse.
    Rules: stay faithful to the lexicon entry and the verse's context; no
    speculation, no "root fallacy" (do not read a word's etymology or other uses
    into this verse), no claims about grammar you are not certain of, no
    sermonising, no quotation marks around the whole answer, no Scripture quoted
    at length. Do not repeat the Strong's number or the transliteration.

    Respond ONLY as minified JSON: {"explanation":"…"}
  PROMPT

  Result = Struct.new(:ok, :text, :error, :provider, keyword_init: true) do
    def ok? = ok
  end

  def self.call(entry:, verse:, word:)
    new(entry:, verse:, word:).call
  end

  def initialize(entry:, verse:, word:)
    @entry = entry
    @verse = verse
    @word = word.to_s.squish[0, 60]
  end

  def call
    return Result.new(ok: false, error: :not_found) unless @entry && @verse

    hit = Rails.cache.read(cache_key)
    return Result.new(ok: true, text: hit[:text], provider: hit[:provider]) if hit.is_a?(Hash)

    res = chat_completion
    return Result.new(ok: false, error: :no_key) if res.error == :no_key
    return Result.new(ok: false, error: :api) unless res.ok?

    text = PlainText.call(parse(res.content), limit: LIMIT).to_s.delete_prefix('"').delete_suffix('"').strip
    return Result.new(ok: false, error: :api) if text.blank?

    Rails.cache.write(cache_key, { text:, provider: res.provider }, expires_in: CACHE_TTL)
    Result.new(ok: true, text:, provider: res.provider)
  rescue => e
    Rails.logger.error("[RootWordExplainer] #{e.class}: #{e.message}")
    Result.new(ok: false, error: :api)
  end

  def cache_key
    "root_word_explainer/v1/#{@entry.strongs}/#{@verse.id}/#{Digest::SHA256.hexdigest(@word.downcase)[0, 16]}"
  end

  private

  # Network seam — overridden in tests.
  def chat_completion
    AiChat.call(system: SYSTEM_PROMPT, user: user_prompt, json: true, temperature: 0.3, max_tokens: MAX_TOKENS)
  end

  def user_prompt
    <<~TEXT
      VERSE: #{@verse.book.name} #{@verse.chapter}:#{@verse.verse_number} (KJV)
      "#{@verse.text}"

      ENGLISH WORD: #{@word.presence || "(not given)"}

      STRONG'S #{@entry.strongs} (#{@entry.language.titleize})
      Lemma: #{@entry.lemma} — #{@entry.translit}
      Definition: #{@entry.definition}
      KJV renders it: #{@entry.kjv_def}
      Derivation: #{@entry.derivation}
    TEXT
  end

  def parse(content)
    cleaned = content.to_s.strip.sub(/\A```(?:json)?\s*/, "").sub(/```\z/, "")
    data = JSON.parse(cleaned)
    data.is_a?(Hash) ? data["explanation"].to_s : ""
  rescue JSON::ParserError
    content.to_s.strip
  end
end
