# The part of the day on the app's home clock (Africa/Lagos, the same day
# boundary as the Word for Today). Home tints itself by it — dawn's warm rose
# and gold, midday's clear parchment light, evening's candlelight — and greets
# the reader to match. A tint layer only: the reader's theme (Vellum, Paper,
# Candlelight, Auto) is never overridden.
#
#   Daypart.at(Time.current).key       # => :dawn | :day | :evening
#   Daypart.at(Time.current).greeting  # => "Good morning"
module Daypart
  Part = Data.define(:key, :greeting, :hour) do
    def label = { dawn: "Dawn", day: "Midday", evening: "Evening" }.fetch(key)
  end

  DAWN = (4..9)
  DAY = (10..16)

  module_function

  def at(time = Time.current)
    hour = time.in_time_zone(DailyWord::TIME_ZONE).hour
    key = if DAWN.cover?(hour) then :dawn
    elsif DAY.cover?(hour) then :day
    else :evening
    end
    Part.new(key:, greeting: greeting_for(hour), hour:)
  end

  def greeting_for(hour)
    case hour
    when 4..11 then "Good morning"
    when 12..16 then "Good afternoon"
    else "Good evening"
    end
  end
end
