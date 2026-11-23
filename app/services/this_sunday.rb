# Pastor mode's "This Sunday" on Home: the service being prepared — the most
# recently opened study with a preach queue (setlist) that hasn't already been
# served on an earlier day (Study::Serving) — its order of service at a
# glance, and what still needs doing before the service. Once the last
# service has happened it is shown as past, with "Plan this Sunday".
#
# Readiness is only what the server can know: songs without an order
# (arrangement), a queue with no scripture. Whether the presentation and the
# Bible are on *this* device is checked on the device (sunday_card controller
# reads what "Get ready for Sunday" recorded).
class ThisSunday
  SHOWN = 4
  Check = Data.define(:state, :text) # state: :ok or :todo

  attr_reader :study, :items, :today

  # The service being prepared, or — when the latest service has already
  # happened (served on an earlier day) and nothing newer is being planned —
  # that last service, as a past one (#past?): Home then shows it briefly with
  # "Plan this Sunday". nil when the account has no queue at all.
  #
  # Being planned = not served before today (or kept with "Keep using it"),
  # and either started for a coming Sunday or opened since the last service
  # (an old queue nobody has touched since last Sunday is not this Sunday's).
  def self.for(user, today: Study.service_today)
    pool = user.studies.unarchived.where(quick_present: false)
    with_queue = pool.where(id: SetlistItem.select(:study_id))
    candidates = pool.where(id: with_queue.select(:id)).or(pool.where(planned_for: today..))
                     .order(Arel.sql("COALESCE(studies.last_opened_at, studies.updated_at) DESC")).limit(50).to_a
    past, current = candidates.partition { |s| s.served_before?(today) }
    last = past.max_by(&:last_served_at)
    since = last&.last_served_at
    upcoming = current.find do |s|
      since.nil? || s.served_on == today || (s.planned_for && s.planned_for >= today) ||
        (s.last_opened_at || s.updated_at) > since || s.kept_for_next_service?
    end
    if upcoming then new(upcoming, today:)
    elsif last then new(last, today:, past: true)
    end
  end

  def initialize(study, today: Study.service_today, past: false)
    @study = study
    @today = today
    @past = past
    @items = study.setlist_items.in_order.select(:id, :kind, :reference, :title, :arrangement, :position,
                                                     Arel.sql("LEFT(setlist_items.body, 120) AS body_head")).to_a
  end

  # The last service already happened: Home offers to plan the next one.
  def past? = @past

  # "Last Sunday, 22 Nov" / "Last service, Wed 18 Nov".
  def served_label
    on = study.served_on
    return "Last service" unless on
    on.sunday? ? "Last Sunday, #{on.strftime('%-d %b')}" : "Last service, #{on.strftime('%a %-d %b')}"
  end

  def shown = items.first(SHOWN)
  def more = [ items.size - SHOWN, 0 ].max

  # The coming Sunday on the app's calendar (today, when it is Sunday).
  def date(day = today) = Study.next_sunday(day)

  def counts
    @counts ||= {
      scripture: items.count { |i| i.scripture? || i.scripture_set? },
      song: items.count(&:song?),
      slides: items.count { |i| !(i.scripture? || i.scripture_set? || i.song?) }
    }
  end

  def checks
    songs = items.select(&:song?)
    unordered = songs.count { |s| s.arrangement.blank? }
    list = []
    if songs.any?
      list << if unordered.zero?
        Check.new(state: :ok, text: "Every song has its order")
      else
        Check.new(state: :todo, text: "#{unordered} #{'song'.pluralize(unordered)} #{unordered == 1 ? 'has' : 'have'} no order yet")
      end
    end
    list << Check.new(state: :todo, text: "No scripture in the order yet") if counts[:scripture].zero?
    list
  end

  # "Scripture", "Song", "Slides" — the kind's label on the order of service.
  def self.kind_label(item)
    case item.kind
    when "scripture", "scripture_set" then "Scripture"
    when "song" then "Song"
    when "picture" then "Picture"
    when "presentation" then "Slides"
    when "seminar" then "Seminar"
    when "word" then "Word study"
    else "Note"
    end
  end

  def self.item_title(item)
    head = item.has_attribute?(:body_head) ? item[:body_head].to_s.strip.lines.first.to_s.strip : ""
    item.title.presence || item.reference.presence || head.presence || kind_label(item)
  end
end
