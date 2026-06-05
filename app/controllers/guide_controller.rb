class GuideController < ApplicationController
  allow_unauthenticated_access only: %i[ show dismiss restore ]
  before_action :require_account, only: %i[ dismiss restore ]

  # The full illustrated tutorial / field guide. Open to everyone.
  def show
    @resume = authenticated? ? current_user.studies.recent.first : nil
  end

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
