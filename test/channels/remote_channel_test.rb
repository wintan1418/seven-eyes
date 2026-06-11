require "test_helper"

class RemoteChannelTest < ActionCable::Channel::TestCase
  test "subscribes to a well-formed code's stream" do
    subscribe code: "abc234"
    assert subscription.confirmed?
    assert_has_stream "remote:ABC234"
  end

  test "rejects a malformed code" do
    subscribe code: "no spaces!"
    assert subscription.rejected?
  end

  test "relays pad commands to everyone on the stream" do
    subscribe code: "ABC234"
    assert_broadcasts("remote:ABC234", 1) do
      perform :relay, { "type" => "command", "action" => "next", "value" => "" }
    end
  end

  test "truncates oversized chase values" do
    subscribe code: "ABC234"
    perform :relay, { "type" => "command", "action" => "chase", "value" => "x" * 500 }
    message = broadcasts("remote:ABC234").last
    assert_operator JSON.parse(message)["value"].length, :<=, 120
  end
end
