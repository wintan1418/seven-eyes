require "test_helper"

class RemotesTest < ActionDispatch::IntegrationTest
  test "the operator mints a pairing code, a console token and a signed pad link" do
    sign_in_as users(:one)
    study = users(:one).studies.create!(name: "Sunday", pane_count: 1)
    post study_remote_path(study), as: :json
    assert_response :success
    data = JSON.parse(response.body)
    assert_match(/\A[A-Z2-9]{6}\z/, data["code"])
    assert_includes data["url"], "/remote/#{data["code"]}?t="
    assert_includes data["qr_svg"], "<svg"
    assert_equal({ role: "console", study_id: study.id }, RemotePairing.verify(data["token"], code: data["code"]))

    pad_token = Rack::Utils.parse_query(URI(data["url"]).query)["t"]
    assert_equal "pad", RemotePairing.verify(pad_token, code: data["code"])[:role]
  end

  test "a guest console can pair a remote for its session study" do
    post studies_path
    post study_remote_path(Study.last), as: :json
    assert_response :success
  end

  test "the pad page renders for a signed link, refuses unsigned ones, 404s malformed codes" do
    study = users(:one).studies.create!(name: "Sunday", pane_count: 1)
    token = RemotePairing.issue(code: "ABC234", study: study, role: RemotePairing::PAD)
    get remote_pad_path("ABC234", t: token)
    assert_response :success
    assert_select ".ps-remote-pad[data-remote-pad-token-value=?] .code", token, text: "ABC234"

    get remote_pad_path("ABC234")
    assert_response :forbidden
    assert_select ".ps-remote-pad.is-unpaired"
    assert_select "[data-controller='remote-pad']", count: 0

    console = RemotePairing.issue(code: "ABC234", study: study, role: RemotePairing::CONSOLE)
    get remote_pad_path("ABC234", t: console)
    assert_response :forbidden, "the console token must not open a pad"

    get remote_pad_path("nope!!")
    assert_response :not_found
  end
end
