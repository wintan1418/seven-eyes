class PlanDaysController < ApplicationController
  before_action :require_account
  before_action :set_day

  def update
    @day.update!(params.require(:plan_day).permit(:refs))
    render partial: "reading_plans/day_row", locals: { plan: @day.reading_plan, day: @day }
  end

  def complete
    @day.create_completion!(reflection: params.dig(:plan_completion, :reflection))
    render partial: "reading_plans/day_row", locals: { plan: @day.reading_plan, day: @day }
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    head :unprocessable_entity
  end

  def uncomplete
    @day.completion&.destroy
    render partial: "reading_plans/day_row", locals: { plan: @day.reading_plan, day: @day }
  end

  private

  def set_day
    plan = current_user.reading_plans.find(params[:reading_plan_id])
    @day = plan.plan_days.find(params[:id])
  end

  def require_account
    return if authenticated?
    head :unauthorized
  end
end
