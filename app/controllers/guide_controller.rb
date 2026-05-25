class GuideController < ApplicationController
  allow_unauthenticated_access only: %i[ dismiss restore ]
  before_action :require_account

  def dismiss
    current_user.update!(guide_dismissed_at: Time.current)
    redirect_back fallback_location: root_path
  end

  def restore
    current_user.update!(guide_dismissed_at: nil)
    redirect_back fallback_location: root_path
  end

  private

  def require_account
    head :unauthorized unless authenticated?
  end
end
