# "Report this answer" on AI output. Open to guests because chapter prayers
# appear on public passage pages; rate-limited so it can't be used to spam.
class AiReportsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 10.minutes, name: "ai-report",
             with: -> { render_thanks(status: :too_many_requests) }

  def create
    AiReport.create!(user: authenticated? ? current_user : nil,
                     kind: params[:kind], context: params[:context], excerpt: params[:excerpt])
    render_thanks
  rescue ActiveRecord::RecordInvalid
    head :unprocessable_entity
  end

  private

  def render_thanks(status: :ok)
    @frame = params[:frame].to_s[/\Aai_report_[a-z0-9_]{1,40}\z/] || "ai_report"
    render :create, layout: false, status: status
  end
end
