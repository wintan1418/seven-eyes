# A reader finished "Today" (Home's guided daily flow) on `date` — the
# Africa/Lagos calendar day of the word they prayed through. One row per
# reader per day; finishing twice is harmless (record! is idempotent).
#
# The streak is consecutive days ending today — or ending yesterday while
# today isn't done yet, so a morning visit doesn't show a broken streak.
class DailyCompletion < ApplicationRecord
  belongs_to :user

  validates :date, presence: true
  # A day may be marked from the device a little late (finished offline, synced
  # the next morning) but never ahead of the calendar or long after.
  LATE_SYNC_DAYS = 3

  # How far back the streak looks: a year of days in one small query.
  STREAK_WINDOW = 400

  class << self
    # Marks the day done; true when this call made the row.
    def record!(user, date)
      date = date.to_date
      today = DailyWord.today_date
      raise ArgumentError, "date out of range" unless date.between?(today - LATE_SYNC_DAYS, today)

      result = insert_all([ { user_id: user.id, date:, created_at: Time.current } ], unique_by: %i[ user_id date ])
      result.rows.any?
    end

    def done_on?(user, date = DailyWord.today_date) = where(user:, date:).exists?

    # Days completed, newest first (enough for any streak).
    def recent_dates(user, today: DailyWord.today_date)
      where(user:, date: (today - STREAK_WINDOW)..today).order(date: :desc).pluck(:date)
    end

    # Streak from a list of dates (any order): consecutive days back from
    # today, or from yesterday when today isn't in the list.
    def streak_from(dates, today: DailyWord.today_date)
      set = dates.to_set
      day = set.include?(today) ? today : today - 1
      count = 0
      while set.include?(day)
        count += 1
        day -= 1
      end
      count
    end

    # Everything Home needs in one query.
    Status = Data.define(:done_today, :streak, :dates)

    def status_for(user, today: DailyWord.today_date)
      dates = recent_dates(user, today:)
      Status.new(done_today: dates.first == today, streak: streak_from(dates, today:), dates:)
    end
  end
end
