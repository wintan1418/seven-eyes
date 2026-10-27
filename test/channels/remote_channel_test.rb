require "test_helper"

class RemoteChannelTest < ActionCable::Channel::TestCase
  setup do
    @study = users(:one).studies.create!(name: "Sunday", pane_count: 1)
  end

  def token(role, code: "ABC234")
    RemotePairing.issue(code: code, study: @study, role: role)
  end

  test "subscribes to a well-formed code's stream with a valid token" do
    subscribe code: "abc234", token: token(RemotePairing::PAD)
    assert subscription.confirmed?
    assert_has_stream "remote:ABC234"
  end

  test "rejects a malformed code" do
    subscribe code: "no spaces!", token: token(RemotePairing::PAD)
    assert subscription.rejected?
  end

  test "rejects a missing, forged, or other-code token" do
    subscribe code: "ABC234"
    assert subscription.rejected?

    subscribe code: "ABC234", token: "forged--token"
    assert subscription.rejected?

    subscribe code: "ABC234", token: token(RemotePairing::PAD, code: "XYZ789")
    assert subscription.rejected?
  end

  test "rejects an expired token" do
    t = token(RemotePairing::PAD)
    travel RemotePairing::TTL + 1.minute do
      subscribe code: "ABC234", token: t
      assert subscription.rejected?
    end
  end

  test "the pad relays commands to everyone on the stream" do
    subscribe code: "ABC234", token: token(RemotePairing::PAD)
    assert_broadcasts("remote:ABC234", 1) do
      perform :relay, { "type" => "command", "command" => "next", "value" => "" }
    end
    # perform() itself injects "action" => "relay"; the console must still see "next".
    assert_equal "next", JSON.parse(broadcasts("remote:ABC234").last)["action"]
  end

  test "the console may only answer presence — never send commands" do
    subscribe code: "ABC234", token: token(RemotePairing::CONSOLE)
    assert_no_broadcasts("remote:ABC234") do
      perform :relay, { "type" => "command", "command" => "next", "value" => "" }
    end
    assert_broadcasts("remote:ABC234", 1) do
      perform :relay, { "type" => "here" }
    end
  end

  test "unknown message types and actions are dropped" do
    subscribe code: "ABC234", token: token(RemotePairing::PAD)
    assert_no_broadcasts("remote:ABC234") do
      perform :relay, { "type" => "here" }
      perform :relay, { "type" => "command", "command" => "format-disk" }
    end
  end

  test "truncates oversized chase values" do
    subscribe code: "ABC234", token: token(RemotePairing::PAD)
    perform :relay, { "type" => "command", "command" => "chase", "value" => "x" * 500 }
    message = broadcasts("remote:ABC234").last
    assert_operator JSON.parse(message)["value"].length, :<=, 120
  end
end
