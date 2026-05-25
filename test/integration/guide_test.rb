require "test_helper"

class GuideTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
  end

  test "dismiss stamps the user and the welcome stops rendering the panel" do
    post dismiss_guide_path
    assert_redirected_to root_path
    follow_redirect!
    assert users(:one).reload.guide_dismissed_at.present?
    refute_match(/What.s at your desk/, response.body)
  end

  test "restore clears the dismissal so the panel reappears" do
    users(:one).update!(guide_dismissed_at: Time.current)
    delete restore_guide_path
    assert_redirected_to root_path
    follow_redirect!
    assert_nil users(:one).reload.guide_dismissed_at
    assert_match(/What.s at your desk/, response.body)
  end

  test "guests cannot dismiss the guide" do
    delete session_path
    post dismiss_guide_path
    assert_response :unauthorized
  end

  test "guests still see the guide on Scriptorium (the JS controller handles hiding for them)" do
    delete session_path
    get root_path
    assert_match(/What.s at your desk/, response.body)
  end
end
