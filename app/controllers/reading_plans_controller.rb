class ReadingPlansController < ApplicationController
  MAX_PANES = 4

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
  # then load today's references into its panes — consecutive chapters of one
  # book share a pane ("Genesis 1-3") when there are more readings than panes.
  #
  # "Today" is Date.current in the app's time zone (UTC — config.time_zone is
  # unset), not the reader's local date; near midnight it can be a day off.
  def open_today
    day = @plan.todays_day
    return redirect_to(@plan, alert: "No reading scheduled for today.") unless day

    refs = day.pane_references(MAX_PANES)
    pane_count = refs.size.clamp(1, MAX_PANES)

    study = @plan.study || current_user.studies.create!(name: "Plan: #{@plan.name}", pane_count:)
    @plan.update!(study: study) if @plan.study.blank?

    if study.pane_count != pane_count
      study.update!(pane_count:)
      study.sync_panes!
    end
    refs.first(MAX_PANES).each_with_index do |ref, idx|
      study.panes.find_by(position: idx)&.update(reference: ref)
    end

    if refs.size > MAX_PANES
      redirect_to study, notice: "Also today: #{refs.drop(MAX_PANES).join(', ')}"
    else
      redirect_to study
    end
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
