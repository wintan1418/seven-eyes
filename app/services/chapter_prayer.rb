require "json"

# Composes a short, shareable prayer drawn from a whole chapter of Scripture.
#
# Like RabbiExposition, it never works from a bare verse — it feeds the model
# the chapter from our own DB and constrains it to pray ONLY from what the text
# actually says, within historic Christian orthodoxy. A finished prayer is cached
# by chapter (it is not user- or translation-specific), so the public share page
# and the in-app share modal reuse the same words and the AI is called at most
# once per chapter.
class ChapterPrayer
  CONTEXT_LIMIT = 80
  CACHE_TTL     = 30.days

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are a reverent pastor composing a short, shareable prayer drawn from one
    chapter of Scripture. Follow these rules strictly:

    1. STAY IN THE TEXT. Pray ONLY from what THIS chapter actually says — its
       themes, its promises, its commands, the character of God it reveals. Do
       not import ideas the chapter does not contain. Do not go beyond what is
       written (1 Corinthians 4:6); no novel doctrine, no private revelation,
       no speculation.
    2. STAY ORTHODOX. Remain within historic Christian orthodoxy — the one true
       God, Father, Son, and Holy Spirit; salvation by grace through faith.
       Address God reverently (Father / Lord / God).
    3. BE CORPORATE. Write in the first person plural ("we", "us") so anyone can
       pray it. Warm, humble, and biblical in tone — not flowery.
    4. BE BRIEF. 80-120 words, one or two short paragraphs. Echo the chapter's
       own language; do not quote long passages verbatim. End with "Amen."

    Respond ONLY as minified JSON with exactly: {"prayer": "..."}
    No text outside the JSON.
  PROMPT

  Result = Struct.new(:ok, :prayer, :reference, :provider, :error, keyword_init: true) do
    def ok? = ok
  end

  def self.call(book:, chapter:, translation: nil)
    new(book:, chapter:, translation:).call
  end

  def initialize(book:, chapter:, translation: nil)
    @book = book
    @chapter = chapter.to_i
    @translation = translation || Translation.find_by(code: "KJV") || Translation.first
  end

  def call
    return error(:no_chapter) unless @book && verses.exists?

    if (cached = Rails.cache.read(cache_key)).present?
      return success(cached)
    end

    res = chat_completion
    return error(:no_key) if res.error == :no_key
    return error(:api)    unless res.ok?

    prayer = parse(res.content)
    return error(:api) if prayer.blank?

    Rails.cache.write(cache_key, prayer, expires_in: CACHE_TTL)
    success(prayer, provider: res.provider)
  rescue => e
    Rails.logger.error("[ChapterPrayer] #{e.class}: #{e.message}")
    error(:api)
  end

  private

  def reference = "#{@book.name} #{@chapter}"
  def cache_key = "chapter_prayer/v1/#{@book.osis_code}/#{@chapter}"

  def verses
    @verses ||= Verse.passage(translation: @translation, book: @book, chapter: @chapter)
  end

  def success(prayer, provider: nil)
    Result.new(ok: true, prayer:, reference:, provider:)
  end

  def error(code) = Result.new(ok: false, error: code, reference:)

  # Network seam — overridden in tests to avoid a live API call.
  def chat_completion
    AiChat.call(system: SYSTEM_PROMPT, user: user_prompt, json: true, temperature: 0.4)
  end

  def user_prompt
    <<~TEXT
      CHAPTER: #{reference} (#{@translation&.name || "KJV"})

      THE TEXT:
      #{chapter_text}

      Compose the prayer from this chapter alone, following every rule above.
    TEXT
  end

  def chapter_text
    verses.limit(CONTEXT_LIMIT).map { |v| "#{v.verse_number}. #{v.text}" }.join("\n")
  end

  def parse(content)
    return nil if content.blank?
    cleaned = content.to_s.strip.sub(/\A```(?:json)?\s*/, "").sub(/```\z/, "")
    JSON.parse(cleaned)["prayer"].to_s.strip.presence
  rescue JSON::ParserError
    nil
  end
end
