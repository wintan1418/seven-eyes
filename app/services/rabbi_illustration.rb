require "json"

# The Rabbi's illustration: turns the highlighted passage into a real, painted
# picture for the congregation — not a schematic line drawing. Two passes:
#   1) a chat pass (AiChat) art-directs a SAFE scene description in the app's
#      illuminated-manuscript aesthetic, or returns "" when there is nothing to
#      depict (a bare argument, doctrine, or genealogy);
#   2) the OpenAI image model (OpenaiImage) renders that scene.
#
# The reverent "illuminated engraving" style is deliberate: it matches the vellum
# design AND avoids photoreal depictions of the divine. Any failure degrades to a
# clear state so the exposition still stands without a picture.
class RabbiIllustration
  CHAPTER_CONTEXT_LIMIT = 60

  MAX_ANNOTATIONS = 5

  # The reverence guardrail every style keeps: the divine shown only as light,
  # never a face.
  REVERENCE = "Portray the divine only as light, cloud, or glory — never a face " \
    "or body; keep it reverent and fit to project in a church.".freeze
  NO_TEXT = " No lettering or text anywhere in the image.".freeze
  # For the labeled look: ONLY small numbered circle badges (digits, never words) —
  # the words live in the legend beneath the image, so nothing can be misspelled.
  MARKERS = " Mark each key element with a small, clean, solid circular badge " \
    "containing ONLY a single digit (1, 2, 3, …) in the order given, joined to its " \
    "element by a thin leader line. Absolutely NO words, names, letters, or captions " \
    "anywhere in the image — ONLY the numbered circles. The labels are supplied separately.".freeze

  # Selectable rendering styles. "realistic" is the clean modern "AI view";
  # "illuminated" is the warm manuscript look; "labeled" annotates the scene with
  # numbered markers that map to the "what to notice" key beneath the image.
  STYLES = {
    "realistic" => " — rendered as a clean, modern, photorealistic cinematic illustration: " \
      "soft natural light, lifelike textures and depth, an uncluttered and elegant composition, " \
      "high detail, dignified. #{REVERENCE}#{NO_TEXT}",
    "illuminated" => " — rendered as an illuminated medieval manuscript illustration / " \
      "fine old Bible engraving: warm vellum tones, sepia ink linework, gold-leaf accents, " \
      "reverent and dignified, painterly, soft light. #{REVERENCE}#{NO_TEXT}",
    "labeled" => " — rendered as a clean, modern educational illustration with an infographic " \
      "feel: crisp, well-lit, uncluttered, the key parts clearly visible. #{REVERENCE}#{MARKERS}"
  }.freeze
  DEFAULT_STYLE = "realistic".freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are an art director and Bible teacher for a reverent study tool. Given a
    highlighted Scripture passage, write ONE vivid prompt describing a single scene
    or object from it to illustrate for a congregation — the setting, figures
    (modest and reverent), objects, landscape, time of day, mood. Ground it strictly
    in the actual passage and its historical setting; invent no unbiblical elements.
    THEN list the vital elements a viewer should notice to understand the passage.

    Reverence rules: portray God or the Lord ONLY as light, cloud, or glory —
    never a face or body. Avoid gore and anything a church could not project. If
    the passage is purely abstract (bare doctrine, an argument, a list of names)
    with nothing to depict, return an empty illustration.

    Respond ONLY as minified JSON:
    {"illustration": "the scene to draw, 1-3 sentences, concrete and visual",
     "caption": "a short caption naming the scene, max 10 words",
     "annotations": [
       {"label": "short name of a key element in the scene, max 6 words",
        "note": "one clause on why it matters / what it means"}
     ]}
    Give 3-5 annotations, ordered by where a marker would sit in the scene (the same
    order the picture should number them). Use an empty illustration and empty
    annotations when there is nothing fitting to illustrate.
  PROMPT

  Annotation = Struct.new(:label, :note, keyword_init: true)

  Result = Struct.new(:ok, :error, :image, :caption, :annotations, :origin, :provider, :style, keyword_init: true) do
    def ok? = ok
  end

  def self.call(verse:, study:, selection: nil, translation: nil, verses: nil, style: nil)
    new(verse:, study:, selection:, translation:, verses:, style:).call
  end

  def initialize(verse:, study:, selection: nil, translation: nil, verses: nil, style: nil)
    @verse = verse
    @verses = Array(verses).compact.presence || [ verse ].compact
    @verse ||= @verses.first
    @selection = selection.to_s.strip[0, RabbiExposition::SELECTION_LIMIT]
    @study = study
    @translation = translation || @verse&.translation
    @style = STYLES.key?(style.to_s) ? style.to_s : DEFAULT_STYLE
  end

  def call
    return error(:no_verse) unless @verse

    art = art_direction
    return error(:no_key) if art.error == :no_key
    return error(:api) unless art.ok?

    data  = parse(art.content)
    scene = data && data["illustration"].to_s.strip
    return error(:none) if scene.blank?

    annotations = build_annotations(data["annotations"])
    img = generate_image(scene + STYLES[@style] + marker_list(annotations))
    return error(img.error || :api) unless img.ok?

    Result.new(ok: true, image: img.data_url, caption: PlainText.call(data["caption"], limit: 120).presence,
               annotations: annotations, origin: origin_label, provider: art.provider, style: @style)
  rescue => e
    Rails.logger.error("[RabbiIllustration] #{e.class}: #{e.message}")
    error(:api)
  end

  private

  def error(code) = Result.new(ok: false, error: code, origin: origin_label, style: @style)

  # Network seams — overridden in tests to avoid live API calls.
  def art_direction = AiChat.call(system: SYSTEM_PROMPT, user: user_prompt, json: true, max_tokens: 800)
  def generate_image(prompt) = OpenaiImage.generate(prompt)

  # The vital points a viewer should notice, shown as a numbered key beneath the
  # image (and, in the "labeled" style, matched to markers drawn on the picture).
  def build_annotations(raw)
    Array(raw).filter_map do |a|
      next unless a.is_a?(Hash)
      label = PlainText.call(a["label"], limit: 80).to_s
      next if label.empty?
      Annotation.new(label: label, note: PlainText.call(a["note"], limit: 240).presence)
    end.first(MAX_ANNOTATIONS)
  end

  # In the labeled style, tell the image model exactly which elements to number,
  # in order, so the on-picture markers line up with the key beneath it.
  def marker_list(annotations)
    return "" unless @style == "labeled" && annotations.any?
    items = annotations.each_with_index.map { |a, i| "#{i + 1}) #{a.label}" }.join("; ")
    " Number these elements in this exact order: #{items}."
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
      #{"HIGHLIGHTED: \"#{@selection}\"\n" if @selection.present?}
      PASSAGE TEXT:
      #{passage_text}

      Describe one reverent scene to illustrate from this passage.
    TEXT
  end

  def passage_text
    Verse.passage(translation: @translation, book: book, chapter: chapter)
         .limit(CHAPTER_CONTEXT_LIMIT)
         .map { |v| "#{v.verse_number}. #{v.text}" }
         .join("\n")
  end

  def parse(content)
    return nil if content.blank?
    cleaned = content.to_s.strip.sub(/\A```(?:json)?\s*/, "").sub(/```\z/, "")
    JSON.parse(cleaned)
  rescue JSON::ParserError
    nil
  end
end
