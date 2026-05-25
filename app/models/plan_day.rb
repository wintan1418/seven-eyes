class PlanDay < ApplicationRecord
  belongs_to :reading_plan, inverse_of: :plan_days
  has_one :completion, class_name: "PlanCompletion", dependent: :destroy

  validates :day_number, presence: true, numericality: { greater_than: 0 }
  validates :day_number, uniqueness: { scope: :reading_plan_id }

  scope :ordered, -> { order(:day_number) }

  # The references as an array (the column stores them comma-separated, since
  # that matches how a user types them and how ReferenceParser already works).
  def reference_list
    refs.to_s.split(/[,;]+/).map(&:strip).reject(&:blank?)
  end

  def date
    reading_plan.start_date + (day_number - 1).days
  end

  def completed? = completion.present?
end
