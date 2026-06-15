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

  # A (re)connecting follower asks for the current state. Action Cable's client
  # re-subscribes silently after a Wi-Fi blip, so without this a phone that
  # dropped mid-service would keep showing a stale verse. We reply to just this
  # subscriber (transmit), not the whole stream.
  def resync
    transmit(@live.live_state) if @live
  end

  private

  def operator?
    params[:role] == "operator"
  end

  def broadcast_count(count)
    self.class.broadcast_to(@live, { type: "count", followers: count })
  end
end
