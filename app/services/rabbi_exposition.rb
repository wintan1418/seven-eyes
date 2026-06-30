require "json"
require "set"

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

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are a careful, reverent biblical expositor — a "Rabbi" in the teacher sense.
    A pastor has highlighted part of a verse and asked what it means. Explain it
    under STRICT rules of sound, historic-orthodox interpretation:

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
    8. DRAW IT WHEN IT HELPS. When the passage describes a physical object,
       structure, or measured layout — the ark, the tabernacle and its curtains,
       the bronze altar, the lampstand, Solomon's or Ezekiel's temple, a vision's
       architecture — a list of cubits puts hearers to sleep. Provide a "diagram"
       so a teacher can SHOW it. For EVERY other passage, leave "diagram" as "".

    Respond ONLY as minified JSON with exactly these keys:
    {
      "summary": "1-2 sentences: the plain meaning of the highlighted words in context.",
      "background": "The world behind the passage — setting, customs, what the first hearers knew that we don't. 2-4 sentences. Use \\"\\" if there is nothing notable.",
      "context": "How the surrounding chapter and genre frame these words.",
      "meaning": "The careful exposition, grounded in the text and the witness of Scripture.",
      "diagram": "USUALLY \\"\\". ONLY when the passage describes a physical object/structure/measured layout, a SIMPLE labelled SVG schematic of it, roughly to scale, showing the given measurements and converting cubits to approximate feet in the labels (1 cubit is about 1.5 ft). Use ONLY <svg><g><rect><line><polyline><polygon><path><circle><ellipse><text><tspan>; include a viewBox (about 0 0 480 320); use SINGLE QUOTES for every attribute value so the JSON stays valid; dark sepia strokes (#3a2a18) with gold (#a3812e) accents on a transparent background; readable <text> labels; NO scripts, NO style attribute, NO external links, NO <image> or <foreignObject>. Keep it compact.",
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

  def self.call(verse:, selection:, study:, translation: nil)
    new(verse:, selection:, study:, translation:).call
  end

  def initialize(verse:, selection:, study:, translation: nil)
    @verse = verse
    @selection = selection.to_s.strip
    @study = study
    @translation = translation || verse&.translation
  end

  def call
    return error(:no_verse) unless @verse
    return error(:blank) if @selection.empty?

    res = chat_completion
    return error(:no_key) if res.error == :no_key
    return error(:api) unless res.ok?

    data = parse(res.content)
    return error(:api) if data.nil?

    Result.new(
      ok: true,
      origin: origin_label,
      selection: @selection,
      exposition: Exposition.new(
        summary: data["summary"], background: data["background"], context: data["context"],
        meaning: data["meaning"], diagram: SvgSanitizer.call(data["diagram"]),
        caution: data["caution"], application: data["application"]
      ),
      cross_references: build_cross_references(data["cross_references"]),
      provider: res.provider
    )
  rescue => e
    Rails.logger.error("[RabbiExposition] #{e.class}: #{e.message}")
    error(:api)
  end

  private

  def error(code) = Result.new(ok: false, error: code, origin: origin_label, selection: @selection)

  # Network seam — overridden in tests to avoid a live API call.
  def chat_completion
    AiChat.call(system: SYSTEM_PROMPT, user: user_prompt, json: true)
  end

  def book    = @verse.book
  def chapter = @verse.chapter

  def origin_label
    return nil unless @verse
    "#{book.name} #{chapter}:#{@verse.verse_number}"
  end

  def user_prompt
    <<~TEXT
      PASSAGE: #{origin_label} (#{@translation&.name || "KJV"})

      HIGHLIGHTED WORDS (what to explain):
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

  def xref_rows
    @xref_rows ||= CrossReferenceLookup.for_verse(
      book: book, chapter: chapter, verse: @verse.verse_number,
      translation: @translation, limit: XREF_LIMIT
    )
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
