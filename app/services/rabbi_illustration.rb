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

  STYLE_SUFFIX = " — rendered as an illuminated medieval manuscript illustration / " \
    "fine old Bible engraving: warm vellum tones, sepia ink linework, gold-leaf accents, " \
    "reverent and dignified, painterly, soft light. No lettering or text in the image. " \
    "Do not depict the face of God; show the divine only as light, cloud, or glory.".freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are an art director for a reverent Bible-study tool. Given a highlighted
    Scripture passage, write ONE vivid prompt describing a single scene or object
    from it to illustrate for a congregation — the setting, figures (modest and
    reverent), objects, landscape, time of day, mood. Ground it strictly in the
    actual passage and its historical setting; invent no unbiblical elements.

    Reverence rules: portray God or the Lord ONLY as light, cloud, or glory —
    never a face or body. Avoid gore and anything a church could not project. If
    the passage is purely abstract (bare doctrine, an argument, a list of names)
    with nothing to depict, return empty strings.

    Respond ONLY as minified JSON:
    {"illustration": "the scene to draw, 1-3 sentences, concrete and visual",
     "caption": "a short caption naming the scene, max 10 words"}
    Use "" for both when there is nothing fitting to illustrate.
  PROMPT

  Result = Struct.new(:ok, :error, :image, :caption, :origin, :provider, keyword_init: true) do
    def ok? = ok
  end

  def self.call(verse:, study:, selection: nil, translation: nil, verses: nil)
    new(verse:, study:, selection:, translation:, verses:).call
  end

  def initialize(verse:, study:, selection: nil, translation: nil, verses: nil)
    @verse = verse
    @verses = Array(verses).compact.presence || [ verse ].compact
    @verse ||= @verses.first
    @selection = selection.to_s.strip
    @study = study
    @translation = translation || @verse&.translation
  end

  def call
    return error(:no_verse) unless @verse

    art = art_direction
    return error(:no_key) if art.error == :no_key
    return error(:api) unless art.ok?

    data  = parse(art.content)
    scene = data && data["illustration"].to_s.strip
    return error(:none) if scene.blank?

    img = generate_image(scene + STYLE_SUFFIX)
    return error(img.error || :api) unless img.ok?

    Result.new(ok: true, image: img.data_url, caption: data["caption"].to_s.strip.presence,
               origin: origin_label, provider: art.provider)
  rescue => e
    Rails.logger.error("[RabbiIllustration] #{e.class}: #{e.message}")
    error(:api)
  end

  private

  def error(code) = Result.new(ok: false, error: code, origin: origin_label)

  # Network seams — overridden in tests to avoid live API calls.
  def art_direction = AiChat.call(system: SYSTEM_PROMPT, user: user_prompt, json: true)
  def generate_image(prompt) = OpenaiImage.generate(prompt)

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
