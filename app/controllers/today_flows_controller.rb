# "Today": Home's guided daily flow (TodayFlow) as one calm, full-screen page
# that steps through the day's verse, passage, reflection, word of the faith,
# prayer and Amen. Open to guests (they keep their streak on the device); the
# service worker saves the page so it works with no signal.
#
# PUT /today/:date/done marks a signed-in reader's day finished. Idempotent,
# so the offline outbox can replay it; dates in the future or more than a few
# days back are refused (422 — the outbox then drops the op).
class TodayFlowsController < ApplicationController
  allow_unauthenticated_access only: :show

  def show
    @word = DailyWord.today
    return redirect_to(root_path) unless @word # no Bible seeded yet

    @daypart = Daypart.at
    @flow = TodayFlow.new(@word, viewer: current_user)
    @status = DailyCompletion.status_for(current_user) if authenticated?
    @art = FaithArt.for_passage(@word&.osis_code || "Ps", DailyWord.today_date)
    @root_lang = @flow.root&.language == "hebrew" ? "he" : "grc"
  end

  def complete
    date = Date.iso8601(params[:date].to_s)
    DailyCompletion.record!(current_user, date)
    status = DailyCompletion.status_for(current_user)
    render json: { ok: true, date: date.iso8601, done_today: status.done_today, streak: status.streak }
  rescue Date::Error, ArgumentError
    render json: { ok: false, error: "That day can't be marked." }, status: :unprocessable_content
  end
end
