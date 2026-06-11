# Pairs the operator console with a phone "clicker" over a short secret code.
# Nothing is persisted: the console mints a code, both ends subscribe to its
# stream, and the channel just relays messages between them —
#   {type: "ping"}                       phone asking if the console is there
#   {type: "here"}                       console answering presence
#   {type: "command", action:, value:}   next / prev / chase from the phone
#
# The code never appears on the projector (unlike the public live join code),
# so only someone shown the pairing QR can drive the screen.
class RemoteChannel < ApplicationCable::Channel
  CODE_FORMAT = /\A[A-Z2-9]{4,12}\z/

  def subscribed
    code = params[:code].to_s.upcase
    return reject unless code.match?(CODE_FORMAT)
    @stream = "remote:#{code}"
    stream_from @stream
  end

  def relay(data)
    return unless @stream
    ActionCable.server.broadcast(@stream, {
      "type" => data["type"].to_s,
      "action" => data["action"].to_s,
      "value" => data["value"].to_s.first(120)
    })
  end
end
