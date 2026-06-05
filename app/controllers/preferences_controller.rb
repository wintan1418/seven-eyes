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
    head :no_content
  end
end
