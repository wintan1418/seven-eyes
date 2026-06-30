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
       architecture — a recital of cubits puts hearers to sleep. Set "draw_subject"
       so a diagram can be drawn for the teacher. For EVERY other passage leave it "".

    Respond ONLY as minified JSON with exactly these keys:
    {
      "summary": "1-2 sentences: the plain meaning of the highlighted words in context.",
      "background": "The world behind the passage — setting, customs, what the first hearers knew that we don't. 2-4 sentences. Use \\"\\" if there is nothing notable.",
      "context": "How the surrounding chapter and genre frame these words.",
      "meaning": "The careful exposition, grounded in the text and the witness of Scripture.",
      "draw_subject": "USUALLY \\"\\". ONLY when the passage describes a physical object/structure/measured layout, a short phrase naming WHAT to draw and the key dimensions to label — e.g. \\"the ark of the covenant: a gold chest 2.5x1.5x1.5 cubits, two cherubim on the lid, carrying poles through gold rings\\" or \\"the tabernacle court: 100x50 cubits, linen curtains 5 cubits high on bronze posts\\". Just the phrase, not a drawing.",
      "cross_references": ["Book C:V", "..."],
      "caution": "What NOT to conclude; where godly interpreters differ; guard against misreading.",
      "application": "A sober, faithful application for teaching or living. May be brief."
    }
    Keep each field tight and pastoral. cross_references: at most 8, standard English
    book names with chapter:verse, ordered by relevance, drawn from those provided or
    plainly relevant. No commentary outside the JSON.
  PROMPT

  # A second, focused pass dedicated to ONE job: drawing. Asking for the SVG on
  # its own (rather than as a field buried in the exposition JSON) is far more
  # reliable — the model actually produces the picture.
  DIAGRAM_PROMPT = <<~PROMPT.freeze
    You are a precise draughtsman drawing a clean, labelled schematic of a biblical
    object for a teacher to show a congregation. Draw it roughly to scale.

    Respond ONLY as minified JSON: {"svg": "<svg>…</svg>"} — the value is a single
    <svg> element and nothing else.
    - viewBox='0 0 480 320'.
    - Use ONLY these tags: <g> <rect> <line> <polyline> <polygon> <path> <circle>
      <ellipse> <text> <tspan> <defs> <linearGradient> <stop>.
    - Use SINGLE QUOTES for every attribute value.
    - Show the given measurements as <text> labels and convert cubits to approximate
      feet in the label (1 cubit ≈ 1.5 ft), e.g. "2.5 cubits (~3.75 ft)".
    - Dark sepia strokes (#3a2a18), gold (#a3812e) fills/accents, transparent
      background, readable labels (font-size 13–16, font-family Georgia, serif).
    - NO script, NO style attribute, NO external links, NO <image>, NO <foreignObject>.
    Keep it uncluttered: the shape, the proportions, and the key labels.
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
        meaning: data["meaning"], diagram: draw_diagram(data["draw_subject"]),
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

  # When the exposition flags a physical subject, draw it in a dedicated call and
  # sanitise the result. Any failure (no key, API error, unusable SVG) simply
  # yields nil so the exposition still renders without a picture.
  def draw_diagram(subject)
    subject = subject.to_s.strip
    return nil if subject.empty?
    res = diagram_completion(subject)
    return nil unless res&.ok?
    SvgSanitizer.from_ai(res.content)
  rescue => e
    Rails.logger.warn("[RabbiExposition] diagram: #{e.class}: #{e.message}")
    nil
  end

  # Network seam for the drawing pass — overridden in tests.
  def diagram_completion(subject)
    AiChat.call(system: DIAGRAM_PROMPT, user: diagram_prompt(subject), json: true)
  end

  def diagram_prompt(subject)
    <<~TEXT
      Passage: #{origin_label}
      Draw this: #{subject}
    TEXT
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
