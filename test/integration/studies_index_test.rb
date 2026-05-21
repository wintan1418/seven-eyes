require "test_helper"

class StudiesIndexTest < ActionDispatch::IntegrationTest
  test "redirects to login when unauthenticated" do
    get root_path
    assert_redirected_to new_session_path
  end

  test "renders the Scriptorium welcome when authenticated" do
    sign_in_as users(:one)
    get root_path
    assert_response :success
    assert_select ".ps-welcome"
    assert_select "h1", text: "Welcome back, Pastor."
  end
end
