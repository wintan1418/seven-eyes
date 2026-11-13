# The pastor's bird's-eye view: who is using the app and what's happening.
# Read-only (apart from re-writing today's Word for Today); only accounts flagged admin (bin/rails admin:grant EMAIL=...) get in.
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
    @ai_reports = AiReport.recent.includes(:user).limit(RECENT_LIMIT)
    @signups_this_week = User.where(created_at: 1.week.ago..).count
    @studies_this_week = Study.where(created_at: 1.week.ago..).count
    @daily_word = DailyWord.find_by(date: DailyWord.today_date)
    @faith_total = FaithTerm.count
    @faith_reviewed = FaithTerm.reviewed.count
  end

  # Ask the AI to write today's reflection and prayer again (e.g. after a
  # report). Synchronous: the admin waits a few seconds and sees the result.
  # On failure the old text stays.
  def regenerate_daily_word
    word = DailyWord.ensure_for(DailyWord.today_date)
    if word&.claim_composition(force: true) && word.compose!
      redirect_to admin_path, notice: "Today's word was rewritten."
    else
      redirect_to admin_path, alert: "The AI couldn't write a new one just now; the old text is kept."
    end
  end

  private

  def require_admin
    return if authenticated? && current_user.admin?
    redirect_to root_path, alert: "That page isn't available."
  end
end
