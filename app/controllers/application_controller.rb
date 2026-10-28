class ApplicationController < ActionController::Base
  include Authentication
  # No allow_browser gate: it answered older church laptops and tablets with a
  # bare 406 page, which inside a Turbo Frame looked like "the fetch failed".
  # Older browsers degrade visually instead of being locked out.

  helper_method :current_user, :authenticated?

  # The iOS/Android apps say so in their user agent, but a service worker's own
  # requests (the pages it saves for offline use) can go out with the plain
  # WebView user agent — and a saved page must still be the app's version
  # (no web tab bar). The apps' cookie jars are their own, not the phone
  # browser's, so the app is remembered in a cookie as well.
  NATIVE_APP_COOKIE = :ps_native_app
  before_action :remember_native_app

  private

  def hotwire_native_app?
    super || cookies[NATIVE_APP_COOKIE] == "1"
  end
  alias_method :turbo_native_app?, :hotwire_native_app?

  def remember_native_app
    return unless request.user_agent.to_s.match?(/(Turbo|Hotwire) Native/)
    return if cookies[NATIVE_APP_COOKIE] == "1"
    cookies.permanent[NATIVE_APP_COOKIE] = { value: "1", httponly: true, same_site: :lax }
  end

  def current_user
    Current.user
  end

  # Resolve a study the requester is allowed to use: their own when signed in,
  # or the single guest study tracked in this browser session.
  def current_study(id)
    if authenticated?
      current_user.studies.find(id)
    else
      study = Study.find(id)
      raise ActiveRecord::RecordNotFound unless study.user_id.nil? && study.id == session[:guest_study_id]
      study
    end
  end

  # After sign-in/registration, adopt any guest study from this session.
  def claim_guest_study(user)
    gid = session.delete(:guest_study_id)
    return unless gid
    study = Study.find_by(id: gid, user_id: nil)
    study&.update(user: user)
    study
  end
end
