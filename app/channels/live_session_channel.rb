# One stream per live session code. Followers (and the operator console)
# subscribe here; the LiveSessionsController broadcasts state changes.
#
# Roles: the operator subscribes with role: "operator" purely to read the
# follower count — only anonymous/pew subscriptions move the counter.
class LiveSessionChannel < ApplicationCable::Channel
  def subscribed
    @live = LiveSession.find_active(params[:code])
    return reject unless @live
    stream_for @live
    return if operator?

    @counted = true
    broadcast_count(@live.adjust_followers(+1))
  end

  def unsubscribed
    return unless @live && @counted
    broadcast_count(@live.adjust_followers(-1))
  end

  private

  def operator?
    params[:role] == "operator"
  end

  def broadcast_count(count)
    self.class.broadcast_to(@live, { type: "count", followers: count })
  end
end
