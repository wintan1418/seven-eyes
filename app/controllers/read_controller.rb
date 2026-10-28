# /read — "open my Bible". The mobile apps' Bible tab starts here: it lands on
# the reader you were last in, or a fresh one at John 3, signed in or not.
class ReadController < ApplicationController
  allow_unauthenticated_access

  DEFAULT_REFERENCE = "John 3".freeze

  # Guests get one study per browser session; don't let /read mint them in bulk.
  rate_limit to: 30, within: 10.minutes, name: "read-create",
             by: -> { request.remote_ip }, only: :show,
             if: -> { !authenticated? && guest_study.nil? },
             with: -> { redirect_to root_path, alert: "Please wait a moment and try again." }

  def show
    redirect_to(authenticated? ? latest_or_new_user_study : guest_study || new_guest_study)
  end

  private

  def latest_or_new_user_study
    current_user.studies.recent.first ||
      current_user.studies.create!(name: "My Bible", pane_count: 1).tap { |s| open_default_passage(s) }
  end

  def guest_study
    @guest_study ||= Study.find_by(id: session[:guest_study_id], user_id: nil) if session[:guest_study_id]
  end

  def new_guest_study
    Study.create!(user: nil, name: "My Bible", pane_count: 1).tap do |study|
      session[:guest_study_id] = study.id
      open_default_passage(study)
    end
  end

  def open_default_passage(study)
    study.panes.first&.update(reference: DEFAULT_REFERENCE)
  end
end
