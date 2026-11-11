require "json"

# Writes the reflection and prayer for a DailyWord.
#
# Like ChapterPrayer, the model never works from a bare verse: it is given the
# passage plus the verses around it from our own DB and told to stay strictly
# inside what the text says. It never supplies Scripture — the verse words on
# the page are always our snapshot. Output is reduced to plain text (PlainText)
# before it is stored. Fails soft: callers get ok: false and show the verse
# alone (no key, AiBudget spent, provider down, unparseable answer).
class DailyWordComposer
  CONTEXT_BEFORE = 6
  CONTEXT_AFTER = 6
  REFLECTION_LIMIT = 900
  PRAYER_LIMIT = 320

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are a warm, careful pastor writing a short "Word for Today" for ordinary
    believers to read on their phones in the morning. You are given today's
    passage and the verses around it. Follow these rules strictly:

    1. STAY IN THE TEXT. Draw only on what this passage and its immediate
       context actually say. Do not invent historical, geographical or
       biographical details, word meanings, statistics, stories or quotations.
       If you are not certain of a fact, leave it out. No novel doctrine and no
       private revelation (1 Corinthians 4:6).
    2. STAY ORTHODOX. Remain within historic Christian orthodoxy — the one true
       God, Father, Son and Holy Spirit; salvation by grace through faith.
    3. REFLECTION: 3 or 4 sentences, plain words, warm and pastoral. Help the
       reader see what the passage says and carry it into today. Speak to
       "you"; no headings, lists, emojis or markup. Do not quote the passage at
       length — the reader already has it in front of them.
    4. PRAYER: one or two short sentences in the first person plural ("we",
       "us"), addressed reverently to God, echoing the passage. End with "Amen."

    Respond ONLY as minified JSON with exactly: {"reflection": "...", "prayer": "..."}
    No text outside the JSON.
  PROMPT

  Result = Struct.new(:ok, :reflection, :prayer, :error, keyword_init: true) do
    def ok? = ok
  end

  def self.call(word)
    new(word).call
  end

  def initialize(word)
    @word = word
  end

  def call
    res = chat_completion
    return error(res.error || :api) unless res.ok?

    reflection, prayer = parse(res.content)
    return error(:api) if reflection.blank? || prayer.blank?

    Result.new(ok: true, reflection:, prayer:)
  rescue => e
    Rails.logger.error("[DailyWordComposer] #{e.class}: #{e.message}")
    error(:api)
  end

  private

  def error(code) = Result.new(ok: false, error: code)

  # Network seam — overridden in tests so no live API is called.
  def chat_completion
    AiChat.call(system: SYSTEM_PROMPT, user: user_prompt, json: true, temperature: 0.4, max_tokens: 700)
  end

  def user_prompt
    <<~TEXT
      TODAY'S PASSAGE: #{@word.reference} (#{@word.translation_code})
      #{@word.verse_text}

      THE SURROUNDING CONTEXT (#{@word.chapter_label}):
      #{context_text}

      Write the reflection and prayer for today's passage, following every rule above.
    TEXT
  end

  def context_text
    book = @word.book
    translation = Translation.find_by(code: @word.translation_code)
    return @word.verse_text unless book && translation

    Verse.passage(translation:, book:, chapter: @word.chapter,
                  verse_start: [ @word.verse_start - CONTEXT_BEFORE, 1 ].max,
                  verse_end: @word.verse_end + CONTEXT_AFTER)
         .map { |v| "#{v.verse_number}. #{v.text}" }.join("\n")
  end

  def parse(content)
    cleaned = content.to_s.strip.sub(/\A```(?:json)?\s*/, "").sub(/```\z/, "")
    data = JSON.parse(cleaned)
    return [] unless data.is_a?(Hash)

    [ PlainText.call(data["reflection"], limit: REFLECTION_LIMIT).presence,
      PlainText.call(data["prayer"], limit: PRAYER_LIMIT).presence ]
  rescue JSON::ParserError
    []
  end
end
