class ReadingPlan < ApplicationRecord
  belongs_to :user
  belongs_to :study, optional: true
  has_many :plan_days, -> { order(:day_number) }, dependent: :destroy, inverse_of: :reading_plan
  has_many :completions, through: :plan_days, source: :completion

  accepts_nested_attributes_for :plan_days, allow_destroy: true

  validates :name, presence: true, length: { maximum: 120 }
  validates :start_date, presence: true

  scope :recent, -> { order(updated_at: :desc) }

  # The day_number that corresponds to a real-world date. Day 1 is the
  # start_date; a later date returns a larger day_number. Negative if before.
  def day_for(date)
    (date - start_date).to_i + 1
  end

  def today_day = day_for(Date.current)

  def todays_day = plan_days.find_by(day_number: today_day)

  def total_days = plan_days.size

  def completed_count = PlanCompletion.joins(:plan_day).where(plan_days: { reading_plan_id: id }).count

  # Current streak counted backward from today across completed days. A gap
  # (an uncompleted past day) breaks the streak.
  def current_streak
    days = plan_days.includes(:completion).index_by(&:day_number)
    streak = 0
    n = today_day
    while n.positive? && days[n]&.completion.present?
      streak += 1
      n -= 1
    end
    streak
  end

  def longest_streak
    best = run = 0
    plan_days.includes(:completion).order(:day_number).each do |d|
      if d.completion
        run += 1
        best = run if run > best
      else
        run = 0
      end
    end
    best
  end
end
