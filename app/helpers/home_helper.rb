# The home page (studies#index): the greeting and small labels.
module HomeHelper
  # "Good morning" by the clock of the app's home congregation — the same
  # day boundary as the Word for today (DailyWord::TIME_ZONE).
  def home_greeting(now = Time.current) = Daypart.at(now).greeting

  # "3 hours ago" (no "about").
  def home_ago(time) = "#{time_ago_in_words(time).delete_prefix('about ').delete_prefix('almost ').delete_prefix('over ')} ago"

  def home_today(now = Time.current) = now.in_time_zone(DailyWord::TIME_ZONE).strftime("%A, %-d %B")

  # The short mark on the Continue reading tile: the book's OSIS code
  # ("Rom", "Ps", "1Cor" → "1 Cor"), or nil for an unreadable reference.
  def home_book_mark(reference)
    parsed = reference.present? ? ReferenceParser.call(reference) : nil
    parsed&.valid? ? parsed.osis.to_s.sub(/\A(\d)/, '\\1 ') : nil
  end

  # The plan's progress ring: an SVG circle whose stroke shows the fraction.
  def home_progress_ring(fraction, size: 64, stroke: 6)
    r = (size - stroke) / 2.0
    c = 2 * Math::PI * r
    dash = (c * fraction.clamp(0, 1)).round(2)
    tag.svg(class: "hm-ring", viewBox: "0 0 #{size} #{size}", width: size, height: size, "aria-hidden": "true") do
      tag.circle(class: "hm-ring-track", cx: size / 2.0, cy: size / 2.0, r:, fill: "none", "stroke-width": stroke) +
        tag.circle(class: "hm-ring-fill", cx: size / 2.0, cy: size / 2.0, r:, fill: "none", "stroke-width": stroke,
                   "stroke-linecap": "round", "stroke-dasharray": "#{dash} #{c.round(2)}",
                   transform: "rotate(-90 #{size / 2.0} #{size / 2.0})")
    end
  end

  # An illuminated initial: the text's first letter as a gilded drop cap
  # (CSS: .il-initial), the rest as it is. Leading quotes stay with the
  # initial so "“Fear not" doesn't strand a quote mark. The initial is an
  # inline span with no space after it, so the word still reads as one.
  # Short text (a verse that may sit on one line, a title) gets a raised
  # initial standing on the baseline; longer prose a true two-line drop cap.
  DROP_CAP_AFTER = 110

  def illuminated(text, tag_name: :span, class_name: nil, drop: nil)
    text = text.to_s
    match = text.match(/\A([\p{Pi}\p{Ps}"'‘“]*)(\p{L})(.*)\z/m)
    return content_tag(tag_name, text, class: class_name) unless match

    lead, letter, rest = match.captures
    drop = text.length > DROP_CAP_AFTER if drop.nil?
    content_tag(tag_name, class: [ "il-text", ("is-drop" if drop), class_name ].compact.join(" ")) do
      tag.span("#{lead}#{letter}", class: "il-initial") + rest
    end
  end

  # A section heading set like a chapter heading in an old Bible: small caps,
  # a gilt fleuron and a thin manuscript rule running out to the right.
  def illuminated_heading(title, id:, level: :h2, aside: nil)
    tag.div(class: "il-heading") do
      content_tag(level, id:, class: "il-heading-title") do
        tag.span(class: "il-fleuron", aria: { hidden: true }) + tag.span(title)
      end + tag.span(class: "il-rule", aria: { hidden: true }) + (aside || "".html_safe)
    end
  end

  # "Day 3 of 21" style fraction as a 0–100 integer, for progress bars.
  def home_percent(part, whole) = whole.to_i.positive? ? ((part.to_f / whole) * 100).round.clamp(0, 100) : 0
end
