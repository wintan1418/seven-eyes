require "set"

# On-demand "Draw this": a single, focused AI pass that takes a passage and
# draws the physical object / structure / measured layout it describes as a
# labelled SVG schematic (the ark, the tabernacle and its curtains, the bronze
# altar, the lampstand, the temple, a vision's architecture). The model is fed
# the surrounding chapter from our own DB for the measurements, and returns ONLY
# an <svg> (or the word NONE). The SVG is run through SvgSanitizer before it ever
# reaches the page. Unlike the exposition's optional diagram, this is the manual
# lever the pastor pulls when they want the picture.
class RabbiDiagram
  CHAPTER_CONTEXT_LIMIT = 80

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are a precise draughtsman. From the Scripture passage given, draw a clean,
    labelled schematic of the physical object, structure, or measured layout it
    describes — the ark, the tabernacle and its curtains, the bronze altar, the
    lampstand, Solomon's or Ezekiel's temple, a vision's architecture — roughly to
    scale, for a teacher to show a congregation.

    If the passage describes nothing physical to draw, output exactly: NONE

    Otherwise output ONLY one <svg>…</svg> element — no prose, no markdown fences, no JSON.
    - viewBox='0 0 480 320'.
    - Use ONLY these tags: <g> <rect> <line> <polyline> <polygon> <path> <circle>
      <ellipse> <text> <tspan> <defs> <linearGradient> <stop>.
    - Show the given measurements as <text> labels and convert cubits to approximate
      feet in the label (1 cubit is about 1.5 ft), e.g. "2.5 cubits (~3.75 ft)".
    - Dark sepia strokes (#3a2a18), gold (#a3812e) fills/accents, transparent
      background, readable labels (font-size 13-16, font-family Georgia, serif).
    - NO script, NO style attribute, NO external links, NO <image>, NO <foreignObject>.
    Keep it uncluttered: the shape, the proportions, and the key labels.
  PROMPT

  Result = Struct.new(:ok, :error, :svg, :origin, :provider, keyword_init: true) do
    def ok? = ok
  end

  def self.call(verse:, selection: nil, study:, translation: nil)
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

    res = chat_completion
    return error(:no_key) if res.error == :no_key
    return error(:api) unless res.ok?

    # No <svg> at all means the model judged there is nothing physical to draw
    # (it returns "NONE"); otherwise hand the markup to the sanitiser.
    content = res.content.to_s
    return error(:none) unless content.match?(/<svg/i)

    svg = SvgSanitizer.call(content)
    return error(:none) unless svg

    Result.new(ok: true, svg: svg, origin: origin_label, provider: res.provider)
  rescue => e
    Rails.logger.error("[RabbiDiagram] #{e.class}: #{e.message}")
    error(:api)
  end

  private

  def error(code) = Result.new(ok: false, error: code, origin: origin_label)

  # Network seam — overridden in tests to avoid a live API call.
  def chat_completion
    AiChat.call(system: SYSTEM_PROMPT, user: user_prompt, json: false)
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
      #{"HIGHLIGHTED: \"#{@selection}\"\n" if @selection.present?}
      FULL CHAPTER (for the measurements) — #{book.name} #{chapter}:
      #{chapter_text}

      Draw the physical thing this passage describes, with its dimensions labelled.
    TEXT
  end

  def chapter_text
    Verse.passage(translation: @translation, book: book, chapter: chapter)
         .limit(CHAPTER_CONTEXT_LIMIT)
         .map { |v| "#{v.verse_number}. #{v.text}" }
         .join("\n")
  end
end
