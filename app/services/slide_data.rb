# The structured part of a queue item (SetlistItem#data), cleaned to a known
# shape before it is saved. The device builds it (scripture set composer,
# presentation import, seminar slide builder); the server only keeps it, so
# nothing here trusts what came in beyond its shape and size.
#
#   scripture_set  { refs: [{ reference, translation, label, verses: [{ c, n, text }] }],
#                    ref_position: top|bottom|inline, verse_numbers: bool,
#                    split: auto|each, ref_style: gold|plain }
#   presentation   { deck, pages, source: pdf|images, file }   — pages stay on the device
#   seminar        { slides: [{ layout, title, text, cite, image, notes }], reveal: bool }
module SlideData
  MAX_REFS = 12
  MAX_VERSES = 80 # per reference
  MAX_PAGES = 300
  MAX_SLIDES = 120
  REF_POSITIONS = %w[ top bottom inline ].freeze
  SPLITS = %w[ auto each ].freeze
  REF_STYLES = %w[ gold plain ].freeze
  SOURCES = %w[ pdf images ].freeze
  LAYOUTS = %w[ title bullets image quote section ].freeze
  DECK_KEY = /\A[\w-]{1,64}\z/
  LOCAL_IMAGE = /\Alocal:[\w-]{1,64}\z/

  module_function

  def clean(kind, raw)
    raw = hashify(raw)
    case kind.to_s
    when "scripture_set" then scripture_set(raw)
    when "presentation" then presentation(raw)
    when "seminar" then seminar(raw)
    else {}
    end
  end

  def scripture_set(raw)
    refs = list(raw["refs"]).first(MAX_REFS).filter_map do |r|
      r = hashify(r)
      verses = list(r["verses"]).first(MAX_VERSES).filter_map do |v|
        v = hashify(v)
        text = str(v["text"], 2000)
        { "c" => v["c"].to_i, "n" => v["n"].to_i, "text" => text } if text.present?
      end
      next if verses.empty?
      { "reference" => str(r["reference"], 80), "translation" => str(r["translation"], 12).upcase,
        "label" => str(r["label"].presence || r["reference"], 80), "verses" => verses }
    end
    {
      "refs" => refs,
      "ref_position" => pick(raw["ref_position"], REF_POSITIONS),
      "verse_numbers" => bool(raw["verse_numbers"], true),
      "split" => pick(raw["split"], SPLITS),
      "ref_style" => pick(raw["ref_style"], REF_STYLES)
    }
  end

  def presentation(raw)
    deck = raw["deck"].to_s
    {
      "deck" => deck.match?(DECK_KEY) ? deck : nil,
      "pages" => raw["pages"].to_i.clamp(0, MAX_PAGES),
      "source" => pick(raw["source"], SOURCES),
      "file" => str(raw["file"], 160).presence
    }.compact
  end

  def seminar(raw)
    slides = list(raw["slides"]).first(MAX_SLIDES).map do |s|
      s = hashify(s)
      image = s["image"].to_s
      {
        "layout" => pick(s["layout"], LAYOUTS),
        "title" => str(s["title"], 300),
        "text" => str(s["text"], 3000),
        "cite" => str(s["cite"], 200),
        "image" => image.match?(LOCAL_IMAGE) ? image : "",
        "notes" => str(s["notes"], 4000)
      }
    end
    { "slides" => slides, "reveal" => bool(raw["reveal"], false) }
  end

  # "Colossians 2:2 KJV + Matthew 28:19 BSB"
  def set_label(data)
    refs = Array(data && data["refs"])
    return "Scripture slide" if refs.empty?
    refs.map { |r| [ r["label"].presence || r["reference"], r["translation"] ].compact_blank.join(" ") }.join(" + ").truncate(120)
  end

  def seminar_label(data)
    first = Array(data && data["slides"]).find { |s| s["title"].present? }
    first ? first["title"].truncate(80) : "Seminar slides"
  end

  def hashify(value)
    value = value.to_unsafe_h if value.respond_to?(:to_unsafe_h)
    value.is_a?(Hash) ? value.to_h.deep_stringify_keys : {}
  end

  def list(value)
    value = value.values if value.is_a?(Hash) || value.respond_to?(:to_unsafe_h) # form-style {"0"=>…}
    Array(value)
  end

  def str(value, max) = value.to_s.strip[0, max]
  def pick(value, allowed) = allowed.include?(value.to_s) ? value.to_s : allowed.first
  def bool(value, default) = value.nil? ? default : ActiveModel::Type::Boolean.new.cast(value) == true
end
