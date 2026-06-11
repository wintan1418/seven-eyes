require "test_helper"

class AdminTest < ActionDispatch::IntegrationTest
  test "guests are sent to sign in" do
    get admin_path
    assert_redirected_to new_session_path
  end

  test "ordinary accounts are turned away" do
    sign_in_as users(:one)
    get admin_path
    assert_redirected_to root_path
  end

  test "an admin sees the overview" do
    users(:one).update!(admin: true)
    users(:one).studies.create!(name: "Sunday", pane_count: 2)
    sign_in_as users(:one)
    get admin_path
    assert_response :success
    assert_includes response.body, "The state of the flock"
    assert_select ".ps-admin .tile .lbl", text: "Users"
    assert_select ".ps-admin td", text: "one@example.com"
    assert_select ".ps-admin td", text: "Sunday"
  end
end
