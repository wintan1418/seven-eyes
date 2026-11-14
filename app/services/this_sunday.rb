# Pastor mode's "This Sunday" on Home: the service being prepared — the most
# recently opened study with a preach queue (setlist) — its order of service
# at a glance, and what still needs doing before the service.
#
# Readiness is only what the server can know: songs without an order
# (arrangement), a queue with no scripture. Whether the presentation and the
# Bible are on *this* device is checked on the device (sunday_card controller
# reads what "Get ready for Sunday" recorded).
class ThisSunday
  SHOWN = 4
  Check = Data.define(:state, :text) # state: :ok or :todo

  attr_reader :study, :items

  def self.for(user)
    study = user.studies.where(quick_present: false).where(id: SetlistItem.select(:study_id))
                .order(Arel.sql("COALESCE(studies.last_opened_at, studies.updated_at) DESC")).first
    study && new(study)
  end

  def initialize(study)
    @study = study
    @items = study.setlist_items.in_order.select(:id, :kind, :reference, :title, :arrangement, :position,
                                                     Arel.sql("LEFT(setlist_items.body, 120) AS body_head")).to_a
  end

  def shown = items.first(SHOWN)
  def more = [ items.size - SHOWN, 0 ].max

  # The coming Sunday on the app's calendar (today, when it is Sunday).
  def date(today = DailyWord.today_date) = today + ((7 - today.wday) % 7)

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
