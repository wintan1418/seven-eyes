class PreferencesController < ApplicationController
  allow_unauthenticated_access only: :update

  def update
    if authenticated? && params[:font_size].present?
      level = params[:font_size].to_i
      Current.user.update_column(:font_size, level) if (0..4).cover?(level)
    end
    # Onboarding tour completion (guests persist this client-side instead).
    if authenticated? && params[:tour_completed].present?
      Current.user.update_column(:tour_completed_at, Time.current)
    end
    # Pastor mode ("This Sunday" on Home), from the switch in More.
    if authenticated? && params.key?(:pastor_mode)
      Current.user.update_column(:pastor_mode, ActiveModel::Type::Boolean.new.cast(params[:pastor_mode]))
      return redirect_back_or_to(more_path) unless request.format.json?
    end
    head :no_content
  end
end
