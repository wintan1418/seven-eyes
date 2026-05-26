class PreferencesController < ApplicationController
  allow_unauthenticated_access only: :update

  def update
    if authenticated? && params[:font_size].present?
      level = params[:font_size].to_i
      Current.user.update_column(:font_size, level) if (0..4).cover?(level)
    end
    head :no_content
  end
end
