require "test_helper"

class RemotesTest < ActionDispatch::IntegrationTest
  test "the operator mints a pairing code with a QR" do
    sign_in_as users(:one)
    study = users(:one).studies.create!(name: "Sunday", pane_count: 1)
    post study_remote_path(study), as: :json
    assert_response :success
    data = JSON.parse(response.body)
    assert_match(/\A[A-Z2-9]{6}\z/, data["code"])
    assert_includes data["url"], "/remote/#{data["code"]}"
    assert_includes data["qr_svg"], "<svg"
  end

  test "a guest console can pair a remote for its session study" do
    post studies_path
    post study_remote_path(Study.last), as: :json
    assert_response :success
  end

  test "the pad page renders for a well-formed code and 404s otherwise" do
    get remote_pad_path("ABC234")
    assert_response :success
    assert_select ".ps-remote-pad .code", text: "ABC234"

    get remote_pad_path("nope!!")
    assert_response :not_found
  end
end
