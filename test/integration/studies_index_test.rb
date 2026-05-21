require "test_helper"

class StudiesIndexTest < ActionDispatch::IntegrationTest
  test "guests can view the open welcome (no forced login)" do
    get root_path
    assert_response :success
    assert_select ".ps-welcome"
  end

  test "renders the Scriptorium welcome when authenticated" do
    sign_in_as users(:one)
    get root_path
    assert_response :success
    assert_select ".ps-welcome"
    assert_select "h1", text: "Welcome back."
  end
end
