require "json"
require "set"
require "digest"

# The "AI Rabbi": explains a highlighted span of Scripture under strict
# interpretive guardrails. It NEVER works from the bare highlighted words —
# it always feeds the model the WHOLE chapter (from our own DB), the verse's
# Treasury-of-Scripture-Knowledge cross-references, and any public-domain
# commentary we hold, then constrains the model to sound, historic-orthodox
# hermeneutics. The model returns structured prose only; every Scripture
# reference it cites is re-validated through ReferenceParser so the words a
# pastor sees always come from our vetted translations, not the LLM.
class RabbiExposition
  CHAPTER_CONTEXT_LIMIT = 80    # verses of surrounding chapter to supply
  XREF_LIMIT            = 14    # cross-references to offer the model
  COMMENTARY_LIMIT      = 2     # public-domain commentary excerpts
  COMMENTARY_CHARS      = 700
  SELECTION_LIMIT       = 500   # chars of highlighted text we send the model
  FIELD_LIMIT           = 2_000 # chars kept per exposition field
  CACHE_TTL             = 7.days
  MAX_TOKENS            = 1_800

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are a careful, reverent biblical expositor — a "Rabbi" in the teacher sense.
    A pastor has highlighted a passage — which may be a single clause OR span
    several verses — and asked what it means. Explain the WHOLE highlighted span,
    not merely its first verse: cover each highlighted verse and how they connect.
    Work under STRICT rules of sound, historic-orthodox interpretation:

    1. CONTEXT FIRST. Never take the highlighted words out of context. Read them in
       light of the WHOLE CHAPTER provided, the immediate sentence, the book's
       argument, and its literary genre (narrative, poetry, law, prophecy, epistle,
       apocalyptic). State plainly what the passage is doing before what it "means to me."
    2. SCRIPTURE INTERPRETS SCRIPTURE. Let the cross-references and the wider biblical
       witness govern the reading. Do not build doctrine on a single clause.
    3. STAY WITHIN THE TEXT. Do NOT go beyond what is written (1 Corinthians 4:6).
       No speculation, no private revelation, no novel doctrines, no date-setting,
       no allegory the text does not warrant, no claims about the original languages
       you are not certain of. If the passage does not answer a question, say so.
    4. GUARD AGAINST HERESY. Stay inside the bounds of historic Christian orthodoxy
       (the authority and sufficiency of Scripture, the Trinity, the full deity and
       humanity of Christ, salvation by grace through faith, bodily resurrection). If a
       possible reading would contradict the broader witness of Scripture, name it as
       a misreading to avoid.
    5. BE HUMBLE AND HONEST. Where godly, orthodox interpreters genuinely differ,
       say so rather than asserting one camp as certain. Distinguish what the text
       clearly teaches from what is reasonable inference.
    6. CITE, DON'T QUOTE. Refer to supporting passages by reference (e.g. "Romans 5:1");
       do NOT reproduce verse text — the application already shows it. Only cite
       references that genuinely bear on the passage.
    7. OPEN THE WORLD BEHIND IT. In "background", give the historical and cultural
       setting an original hearer assumed but a modern reader misses — customs,
       institutions, geography, the practices of that time (especially rich for OT
       narrative and law: Exodus, Leviticus, the Gospels' Jewish world).

    Respond ONLY as minified JSON with exactly these keys:
    {
      "summary": "1-2 sentences: the plain meaning of the highlighted words in context.",
      "background": "The world behind the passage — setting, customs, what the first hearers knew that we don't. 2-4 sentences. Use \\"\\" if there is nothing notable.",
      "context": "How the surrounding chapter and genre frame these words.",
      "meaning": "The careful exposition, grounded in the text and the witness of Scripture.",
      "cross_references": ["Book C:V", "..."],
      "caution": "What NOT to conclude; where godly interpreters differ; guard against misreading.",
      "application": "A sober, faithful application for teaching or living. May be brief."
    }
    Keep each field tight and pastoral. cross_references: at most 8, standard English
    book names with chapter:verse, ordered by relevance, drawn from those provided or
    plainly relevant. No commentary outside the JSON.
  PROMPT

  Exposition = Struct.new(:summary, :background, :context, :meaning, :diagram, :caution, :application, keyword_init: true)
  CrossRef   = Struct.new(:reference, :osis, :chapter, :verse_start, :verse_end, keyword_init: true)

  Result = Struct.new(:ok, :error, :origin, :selection, :exposition, :cross_references, :provider, keyword_init: true) do
    def ok? = ok
  end

  def self.call(verse:, selection:, study:, translation: nil, verses: nil)
    new(verse:, selection:, study:, translation:, verses:).call
  end

  def initialize(verse:, selection:, study:, translation: nil, verses: nil)
    @verse = verse
    # The pastor may highlight a span of verses (John 3:16-18), not just one.
    # @verses is the full highlighted set (ordered); @verse anchors the chapter.
    @verses = Array(verses).compact.presence || [ verse ].compact
    @verse ||= @verses.first
    @selection = selection.to_s.strip[0, SELECTION_LIMIT]
    @study = study
    @translation = translation || @verse&.translation
  end

  def call
    return error(:no_verse) unless @verse
    return error(:blank) if @selection.empty?

    payload = cached_exposition
    return error(payload) if payload.is_a?(Symbol)

    data = payload[:data]
    Result.new(
      ok: true,
      origin: origin_label,
      selection: @selection,
      # Model output is reduced to plain text — no markup (and so no injected
      # links) can reach the page. The measured diagram is NOT drawn here: the
      # drawer's "Draw this passage" button (RabbiDiagram) does that on demand,
      # so an exposition costs one model call, not two.
      exposition: Exposition.new(
        summary: clean(data["summary"]), background: clean(data["background"]),
        context: clean(data["context"]), meaning: clean(data["meaning"]), diagram: nil,
        caution: clean(data["caution"]), application: clean(data["application"])
      ),
      cross_references: build_cross_references(data["cross_references"]),
      provider: payload[:provider]
    )
  rescue => e
    Rails.logger.error("[RabbiExposition] #{e.class}: #{e.message}")
    error(:api)
  end

  # Same verses + translation + highlighted words => same answer: cache it so a
  # re-ask (or a second pastor on John 3:16) never pays for the model twice.
  def cache_key
    digest = Digest::SHA256.hexdigest(@selection.downcase.squish)
    "rabbi_exposition/v2/#{@translation&.id}/#{@verses.map(&:id).sort.join("-")}/#{digest}"
  end

  private

  def error(code) = Result.new(ok: false, error: code, origin: origin_label, selection: @selection)

  # Returns { data:, provider: } (cached on success) or an error Symbol.
  def cached_exposition
    hit = Rails.cache.read(cache_key)
    return hit if hit.is_a?(Hash)

    res = chat_completion
    return :no_key if res.error == :no_key
    return :api unless res.ok?

    data = parse(res.content)
    return :api unless data.is_a?(Hash)

    payload = { data: data, provider: res.provider }
    Rails.cache.write(cache_key, payload, expires_in: CACHE_TTL)
    payload
  end

  def clean(text) = PlainText.call(text, limit: FIELD_LIMIT).presence

  # Network seam — overridden in tests to avoid a live API call.
  def chat_completion
    AiChat.call(system: SYSTEM_PROMPT, user: user_prompt, json: true, max_tokens: MAX_TOKENS)
  end

  def book    = @verse.book
  def chapter = @verse.chapter

  def origin_label
    return nil unless @verse
    nums = @verses.map(&:verse_number)
    first, last = nums.min, nums.max
    range = (first == last) ? first.to_s : "#{first}–#{last}"
    "#{book.name} #{chapter}:#{range}"
  end

  def user_prompt
    <<~TEXT
      PASSAGE: #{origin_label} (#{@translation&.name || "KJV"})

      HIGHLIGHTED TEXT (explain ALL of this — it may span several verses):
      "#{@selection}"

      FULL CHAPTER FOR CONTEXT — #{book.name} #{chapter}:
      #{chapter_text}

      CROSS-REFERENCES (Treasury of Scripture Knowledge, most-cited first):
      #{xref_lines.presence || "(none on record)"}

      #{commentary_block}
      Explain the highlighted words for sermon preparation, following every rule above.
    TEXT
  end

  def chapter_text
    Verse.passage(translation: @translation, book: book, chapter: chapter)
         .limit(CHAPTER_CONTEXT_LIMIT)
         .map { |v| "#{v.verse_number}. #{v.text}" }
         .join("\n")
  end

  # Gather cross-references for EVERY highlighted verse (not just the first),
  # merged in order and de-duplicated, so a highlighted span is served fully.
  def xref_rows
    @xref_rows ||= begin
      seen = Set.new
      @verses.flat_map do |v|
        CrossReferenceLookup.for_verse(
          book: book, chapter: chapter, verse: v.verse_number,
          translation: @translation, limit: XREF_LIMIT
        )
      end.select { |r| seen.add?(r.reference) }.first(XREF_LIMIT)
    end
  end

  def xref_lines
    xref_rows.map { |r| "- #{r.reference}" }.join("\n")
  end

  def commentary_block
    entries = Commentary.for_chapter(book, chapter).limit(COMMENTARY_LIMIT)
    return "" if entries.empty?
    body = entries.map { |c| "[#{c.source_name}] #{c.body.to_s.truncate(COMMENTARY_CHARS)}" }.join("\n\n")
    "PUBLIC-DOMAIN COMMENTARY (for reference only, weigh against the text):\n#{body}\n\n"
  end

  # Re-validate every reference the model offers through ReferenceParser, dropping
  # anything unparseable/unknown/duplicate, so the UI can load it from our own DB.
  def build_cross_references(refs)
    seen = Set.new
    Array(refs).first(8).filter_map do |raw|
      parsed = ReferenceParser.call(raw)
      next unless parsed.valid?
      key = [ parsed.osis, parsed.chapter, parsed.verse_start ]
      next if seen.include?(key)
      seen << key
      next unless Book.find_by_osis(parsed.osis)

      CrossRef.new(
        reference: parsed.label, osis: parsed.osis, chapter: parsed.chapter,
        verse_start: parsed.verse_start, verse_end: parsed.verse_end
      )
    end
  end

  def parse(content)
    return nil if content.blank?
    # Models occasionally wrap JSON in ```json fences; strip them defensively.
    cleaned = content.to_s.strip.sub(/\A```(?:json)?\s*/, "").sub(/```\z/, "")
    JSON.parse(cleaned)
  rescue JSON::ParserError
    nil
  end
end
