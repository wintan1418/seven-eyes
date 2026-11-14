# The home page (studies#index): the greeting and small labels.
module HomeHelper
  # "Good morning" by the clock of the app's home congregation — the same
  # day boundary as the Word for today (DailyWord::TIME_ZONE).
  def home_greeting(now = Time.current)
    hour = now.in_time_zone(DailyWord::TIME_ZONE).hour
    case hour
    when 4..11 then "Good morning"
    when 12..16 then "Good afternoon"
    else "Good evening"
    end
  end

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
end
