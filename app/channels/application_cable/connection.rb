module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    # Connections are open to guests: live "follow along" sessions are joined
    # anonymously from the pews. Channels that need an account must check
    # current_user themselves.
    def connect
      self.current_user = find_session_user
    end

    private
      def find_session_user
        if session = Session.find_by(id: cookies.signed[:session_id])
          session.user
        end
      end
  end
end
