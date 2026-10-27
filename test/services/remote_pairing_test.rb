require "test_helper"

class RemotePairingTest < ActiveSupport::TestCase
  setup do
    @study = users(:one).studies.create!(name: "Sunday", pane_count: 1)
  end

  test "a token verifies for its own code and carries role and study" do
    token = RemotePairing.issue(code: "abc234", study: @study, role: RemotePairing::PAD)
    assert_equal({ role: "pad", study_id: @study.id }, RemotePairing.verify(token, code: "ABC234"))
  end

  test "a token is bound to its code" do
    token = RemotePairing.issue(code: "ABC234", study: @study, role: RemotePairing::CONSOLE)
    assert_nil RemotePairing.verify(token, code: "ABC235")
  end

  test "tokens expire" do
    token = RemotePairing.issue(code: "ABC234", study: @study, role: RemotePairing::PAD)
    travel RemotePairing::TTL + 1.second do
      assert_nil RemotePairing.verify(token, code: "ABC234")
    end
  end

  test "garbage and blanks don't verify" do
    assert_nil RemotePairing.verify(nil, code: "ABC234")
    assert_nil RemotePairing.verify("", code: "ABC234")
    assert_nil RemotePairing.verify("not-a-token", code: "ABC234")
  end

  test "only known roles can be issued" do
    assert_raises(ArgumentError) { RemotePairing.issue(code: "ABC234", study: @study, role: "admin") }
  end
end
