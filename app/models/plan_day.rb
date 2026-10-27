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

  # The day's references fitted into at most +max+ panes. When there are more
  # references than panes, consecutive whole chapters of one book are combined
  # into a range ("Genesis 1, Genesis 2, Genesis 3" -> "Genesis 1-3"), which a
  # pane loads as one multi-chapter passage. May still exceed +max+ when the
  # readings span more books than panes; callers report the overflow.
  def pane_references(max = 4)
    refs = reference_list
    return refs if refs.size <= max

    runs = []
    refs.each do |ref|
      parsed = ReferenceParser.call(ref)
      last = runs.last
      if parsed.valid? && parsed.whole_chapter? && last&.dig(:parsed)&.whole_chapter? &&
         last[:parsed].osis == parsed.osis && parsed.chapter == last[:last_chapter] + 1
        last[:last_chapter] = parsed.last_chapter
      else
        runs << { ref:, parsed: (parsed if parsed.valid?), last_chapter: parsed.valid? ? parsed.last_chapter : nil }
      end
    end
    runs.map do |run|
      p = run[:parsed]
      p && run[:last_chapter] > p.chapter ? "#{p.book_name} #{p.chapter}-#{run[:last_chapter]}" : run[:ref]
    end
  end

  def date
    reading_plan.start_date + (day_number - 1).days
  end

  def completed? = completion.present?
end
