# /read — "open my Bible". The mobile apps' Bible tab starts here: it lands on
# the reader you were last in, or a fresh one at John 3, signed in or not.
# /read?ref=Deut+32:2&t=KJV (search results) opens that reader at the whole
# chapter, scrolled to the verse and marked (ChapterFocus + verse-focus).
class ReadController < ApplicationController
  allow_unauthenticated_access

  DEFAULT_REFERENCE = "John 3".freeze

  # Guests get one study per browser session; don't let /read mint them in bulk.
  rate_limit to: 30, within: 10.minutes, name: "read-create",
             by: -> { request.remote_ip }, only: :show,
             if: -> { !authenticated? && guest_study.nil? },
             with: -> { redirect_to root_path, alert: "Please wait a moment and try again." }

  def show
    # The service worker saving /read for offline use (X-Offline-Precache)
    # opens the reader's study but never makes one: a guest who only looked
    # at the sign-in page mustn't get a study claimed into their account.
    # With none, offline /read opens the device's offline reader instead.
    return head(:no_content) if precache? && existing_study.nil?

    study = authenticated? ? latest_or_new_user_study : guest_study || new_guest_study
    return redirect_to(study) if params[:ref].blank?

    focus = ChapterFocus.call(params[:ref].to_s.first(80))
    pane = study.panes.first
    attrs = { reference: focus.reference }
    translation = Translation.available.find_by(code: params[:t].to_s.upcase.presence)
    attrs[:translation] = translation if translation
    pane&.update(attrs)
    redirect_to study_path(study, verse: focus.verses)
  end

  private

  def precache? = request.headers["X-Offline-Precache"].present?

  def existing_study
    authenticated? ? current_user.studies.where(quick_present: false).recent.first : guest_study
  end

  def latest_or_new_user_study
    # Quick Present is for the pulpit, not the Bible tab.
    current_user.studies.where(quick_present: false).recent.first ||
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
