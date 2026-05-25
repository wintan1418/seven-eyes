class PlanCompletion < ApplicationRecord
  belongs_to :plan_day

  validates :plan_day_id, uniqueness: true
  validates :completed_at, presence: true

  before_validation :stamp_now, on: :create

  private

  def stamp_now
    self.completed_at ||= Time.current
  end
end
