# Pairs the operator console with a phone "clicker". The console mints a code
# plus two signed, expiring pairing tokens (RemotePairing) — one for itself,
# one baked into the pad's QR link — and both ends subscribe with theirs:
#   {type: "ping"}                       pad asking if the console is there
#   {type: "here"}                       console answering presence
#   {type: "command", action:, value:}   next / prev / chase from the pad
#
# A subscription must present a valid token for that code; only the pad role
# may send commands and pings, only the console may answer "here". Knowing a
# code alone (it's printed on the pad) is not enough to join the stream.
class RemoteChannel < ApplicationCable::Channel
  CODE_FORMAT = /\A[A-Z2-9]{4,12}\z/

  PAD_MESSAGES = %w[ ping command ].freeze
  CONSOLE_MESSAGES = %w[ here ].freeze
  COMMANDS = %w[ next prev back home blank chase ].freeze

  def subscribed
    code = params[:code].to_s.upcase
    return reject unless code.match?(CODE_FORMAT)
    pairing = RemotePairing.verify(params[:token], code: code)
    return reject unless pairing
    @role = pairing[:role]
    @stream = "remote:#{code}"
    stream_from @stream
  end

  # The pad sends its command name as `command`: Action Cable's client
  # `perform("relay", data)` overwrites data.action with "relay", so an
  # `action` key never survives the trip. The relayed message keeps the
  # console-facing `action` field.
  def relay(data)
    return unless @stream
    type = data["type"].to_s
    allowed = @role == RemotePairing::PAD ? PAD_MESSAGES : CONSOLE_MESSAGES
    return unless allowed.include?(type)
    command = data["command"].to_s
    return if type == "command" && !COMMANDS.include?(command)

    ActionCable.server.broadcast(@stream, {
      "type" => type,
      "action" => command,
      "value" => data["value"].to_s.first(120)
    })
  end
end
