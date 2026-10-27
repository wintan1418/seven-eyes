# One stream per live session code. Followers subscribe here; the
# LiveSessionsController broadcasts state changes to them.
#
# Roles:
#   follower (default) — anonymous phones in the pews. Streams the session's
#                        state and moves the follower counter.
#   operator           — the preaching console, proven by the signed
#                        `operator_token` it got when it went live. Streams
#                        ONLY the operator side-channel (the "N following"
#                        count) so followers never receive count chatter.
class LiveSessionChannel < ApplicationCable::Channel
  def self.operator_broadcasting_for(live)
    broadcasting_for([ live, :operator ])
  end

  def self.broadcast_count(live, count)
    ActionCable.server.broadcast(operator_broadcasting_for(live), { type: "count", followers: count })
  end

  def subscribed
    return subscribe_operator if params[:role] == "operator"

    @live = LiveSession.find_active(params[:code])
    return reject unless @live
    stream_for @live
    @counted = true
    self.class.broadcast_count(@live, @live.adjust_followers(+1))
  end

  def unsubscribed
    return unless @live && @counted
    self.class.broadcast_count(@live, @live.adjust_followers(-1))
  end

  # A (re)connecting follower asks for the current state. Action Cable's client
  # re-subscribes silently after a Wi-Fi blip, so without this a phone that
  # dropped mid-service would keep showing a stale verse. We reply to just this
  # subscriber (transmit), not the whole stream.
  def resync
    transmit(@live.reload.live_state) if @live && @counted
  end

  private

  def subscribe_operator
    live = LiveSession.find_by_operator_token(params[:token])
    return reject unless live && !live.ended? &&
                         live.code == LiveSession.normalize_code(params[:code])
    @live = live
    stream_from self.class.operator_broadcasting_for(live)
    transmit({ type: "count", followers: live.followers_count })
  end
end
