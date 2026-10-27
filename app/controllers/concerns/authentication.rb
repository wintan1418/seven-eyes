module Authentication
  extend ActiveSupport::Concern

  # Keys carried across the session reset at sign-in: the guest's study (so
  # claim_guest_study can adopt it) and where to send the user afterwards.
  PRESERVED_SESSION_KEYS = %i[ guest_study_id return_to_after_authenticating ].freeze

  included do
    before_action :require_authentication
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      resume_session
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    # Sessions expire (Session::TTL); an expired row is removed on sight.
    def find_session_by_cookie
      id = cookies.signed[:session_id]
      return unless id
      session_record = Session.find_by(id: id)
      return session_record if session_record.nil? || !session_record.expired?
      session_record.destroy
      cookies.delete(:session_id)
      nil
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.url
      redirect_to new_session_path
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || root_url
    end

    def start_new_session_for(user)
      # New Rails session id on sign-in: defeats session fixation.
      carried = PRESERVED_SESSION_KEYS.index_with { |k| session[k] }.compact
      reset_session
      carried.each { |k, v| session[k] = v }

      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        Current.session = session
        cookies.signed[:session_id] = { value: session.id, httponly: true, same_site: :lax,
                                        expires: Session::TTL.from_now }
      end
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
