# The structured part of a queue item (SetlistItem#data), cleaned to a known
# shape before it is saved. The device builds it (scripture set composer,
# presentation import, seminar slide builder); the server only keeps it, so
# nothing here trusts what came in beyond its shape and size.
#
#   scripture_set  { refs: [{ reference, translation, label, own, verses: [{ c, n, text }] }],
#                    ref_position: top|bottom|inline, verse_numbers: bool,
#                    split: auto|each|one, ref_style: gold|plain, per_slide: 0..6,
#                    combined: bool }
#                  split "one" + combined: "Combine into one slide" — every verse on a
#                  single slide; verse text may carry emphasis marks (**bold**, ==highlight==).
#                  A ref with `own` holds words the pastor pasted from their own
#                  Bible (NKJV, NIV, AMP…) — the version is just their label; the
#                  words live only in this item. n 0 = a piece of an unnumbered paste.
#   presentation   { deck, pages, source: pdf|images, file }   — pages stay on the device
#   seminar        { slides: [{ layout, title, text, cite, image, notes }], reveal: bool }
#   picture        { fit: fit|fill|stretch, zoom: 100..200 }   — how it fills the projector
module SlideData
  MAX_REFS = 12
  MAX_VERSES = 80 # per reference
  MAX_OWN_VERSES = 200 # per pasted ("own") reference
  OWN_TEXT_BYTES = 40_000 # the pasted words of one item
  PER_SLIDE = (0..6) # verses a slide; 0 = as many as fit
  MAX_PAGES = 300
  MAX_SLIDES = 120
  REF_POSITIONS = %w[ top bottom inline ].freeze
  SPLITS = %w[ auto each one ].freeze
  REF_STYLES = %w[ gold plain ].freeze
  SOURCES = %w[ pdf images ].freeze
  LAYOUTS = %w[ title bullets image quote section ].freeze
  # How a picture fills the screen (EasyWorship's "scaling"): fit = the whole
  # picture, black bars where its shape differs (the default — nothing of a
  # flyer is ever cut off); fill = covers the screen, the edges cropped;
  # stretch = pulled to the screen's shape. Zoom enlarges it from the centre.
  PICTURE_FITS = %w[ fit fill stretch ].freeze
  PICTURE_ZOOM = (100..200)
  DECK_KEY = /\A[\w-]{1,64}\z/
  LOCAL_IMAGE = /\Alocal:[\w-]{1,64}\z/

  module_function

  def clean(kind, raw)
    raw = hashify(raw)
    case kind.to_s
    when "scripture_set" then scripture_set(raw)
    when "presentation" then presentation(raw)
    when "seminar" then seminar(raw)
    when "picture" then picture(raw)
    else {}
    end
  end

  def scripture_set(raw)
    refs = list(raw["refs"]).first(MAX_REFS).filter_map do |r|
      r = hashify(r)
      own = bool(r["own"], false)
      verses = list(r["verses"]).first(own ? MAX_OWN_VERSES : MAX_VERSES).filter_map do |v|
        v = hashify(v)
        text = str(v["text"], 2000)
        { "c" => v["c"].to_i.clamp(0, 200), "n" => v["n"].to_i.clamp(0, 200), "text" => text } if text.present?
      end
      next if verses.empty?
      ref = { "reference" => str(r["reference"], 80), "translation" => str(r["translation"], 12).upcase,
              "label" => str(r["label"].presence || r["reference"], 80), "verses" => verses }
      own ? ref.merge("own" => true) : ref
    end
    set = {
      "refs" => refs,
      "ref_position" => pick(raw["ref_position"], REF_POSITIONS),
      "verse_numbers" => bool(raw["verse_numbers"], true),
      "split" => pick(raw["split"], SPLITS),
      "ref_style" => pick(raw["ref_style"], REF_STYLES),
      "per_slide" => raw["per_slide"].to_i.clamp(PER_SLIDE.min, PER_SLIDE.max)
    }
    bool(raw["combined"], false) ? set.merge("combined" => true) : set
  end

  # Does this scripture set hold words pasted from the pastor's own Bible?
  def own?(data)
    Array(data && data["refs"]).any? { |r| r.is_a?(Hash) && r["own"] == true }
  end

  def own_text_bytes(data)
    Array(data && data["refs"]).select { |r| r["own"] }.sum { |r| Array(r["verses"]).sum { |v| v["text"].to_s.bytesize } }
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

  def picture(raw)
    zoom = raw["zoom"].to_i
    zoom = PICTURE_ZOOM.min if zoom.zero?
    { "fit" => pick(raw["fit"], PICTURE_FITS), "zoom" => zoom.clamp(PICTURE_ZOOM.min, PICTURE_ZOOM.max) }
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
