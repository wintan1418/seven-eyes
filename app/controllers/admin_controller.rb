# The pastor's bird's-eye view: who is using the app and what's happening.
# Read-only; only accounts flagged admin (bin/rails admin:grant EMAIL=...) get in.
class AdminController < ApplicationController
  before_action :require_admin

  RECENT_LIMIT = 12

  def show
    @totals = {
      "Users" => User.count,
      "Studies" => Study.count,
      "Guest studies" => Study.where(user_id: nil).count,
      "Panes" => Pane.count,
      "Notes" => Pane.where.not(notes: [ nil, "" ]).count,
      "Highlights" => Highlight.count,
      "Queue items" => SetlistItem.count,
      "Reading plans" => ReadingPlan.count,
      "Live sessions" => LiveSession.count
    }
    @live_now = LiveSession.active.where.not(osis: nil).order(created_at: :desc)
                           .includes(:study).limit(RECENT_LIMIT)
    @recent_users = User.order(created_at: :desc).includes(:studies).limit(RECENT_LIMIT)
    @recent_studies = Study.recent.includes(:user).limit(RECENT_LIMIT)
    @recent_lives = LiveSession.order(created_at: :desc).includes(:study).limit(RECENT_LIMIT)
    @signups_this_week = User.where(created_at: 1.week.ago..).count
    @studies_this_week = Study.where(created_at: 1.week.ago..).count
  end

  private

  def require_admin
    return if authenticated? && current_user.admin?
    redirect_to root_path, alert: "That page isn't available."
  end
end
