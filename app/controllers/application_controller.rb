class ApplicationController < ActionController::Base
  include Authentication
  # No allow_browser gate: it answered older church laptops and tablets with a
  # bare 406 page, which inside a Turbo Frame looked like "the fetch failed".
  # Older browsers degrade visually instead of being locked out.

  helper_method :current_user, :authenticated?

  private

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
