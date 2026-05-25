class ReadingPlansController < ApplicationController
  before_action :require_account
  before_action :set_plan, only: %i[ show destroy open_today ]

  def index
    @plans = current_user.reading_plans.recent
  end

  def new
    @plan = current_user.reading_plans.new(start_date: Date.current)
    @books = Book.order(:position)
  end

  def create
    permitted = params.require(:reading_plan).permit(:name, :description, :start_date, :template, :book, :chapters_per_day, :days)
    template = permitted.delete(:template).presence || "empty"
    template_options = {
      book: permitted.delete(:book),
      chapters_per_day: permitted.delete(:chapters_per_day),
      days: permitted.delete(:days)
    }

    plan = current_user.reading_plans.new(permitted)
    plan.start_date ||= Date.current
    plan.name = "Untitled Plan" if plan.name.blank?

    ReadingPlan.transaction do
      plan.save!
      PlanTemplate.build(template, template_options).each do |attrs|
        plan.plan_days.create!(attrs)
      end
    end
    redirect_to plan
  rescue ActiveRecord::RecordInvalid => e
    @plan = plan
    @books = Book.order(:position)
    flash.now[:alert] = e.message
    render :new, status: :unprocessable_entity
  end

  def show
    @days = @plan.plan_days.includes(:completion).ordered
    @today = @plan.today_day
  end

  def destroy
    @plan.destroy
    redirect_to reading_plans_path, status: :see_other
  end

  # Open today's reading in a study: create the plan's study on first use,
  # then load each of today's references into a separate pane.
  def open_today
    day = @plan.todays_day
    return redirect_to(@plan, alert: "No reading scheduled for today.") unless day

    study = @plan.study || current_user.studies.create!(
      name: "Plan: #{@plan.name}",
      pane_count: [ day.reference_list.size.clamp(1, 4), 1 ].max
    )
    @plan.update!(study: study) if @plan.study.blank?

    # Resize panes to match today's reference count (1-4) and load refs into them.
    pane_count = day.reference_list.size.clamp(1, 4)
    if pane_count.positive? && study.pane_count != pane_count
      study.update!(pane_count:)
      study.sync_panes!
    end
    day.reference_list.first(4).each_with_index do |ref, idx|
      pane = study.panes.find_by(position: idx)
      pane&.update(reference: ref)
    end

    redirect_to study
  end

  private

  def set_plan
    @plan = current_user.reading_plans.find(params[:id])
  end

  def require_account
    return if authenticated?
    redirect_to new_session_path, alert: "Sign in to use reading plans."
  end
end
