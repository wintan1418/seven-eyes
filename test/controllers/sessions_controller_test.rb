require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = User.take }

  test "new" do
    get new_session_path
    assert_response :success
  end

  test "create with valid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "password" }

    assert_redirected_to root_path
    assert cookies[:session_id]
  end

  test "create with invalid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "wrong" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
  end

  test "destroy" do
    sign_in_as(User.take)

    delete session_path

    assert_redirected_to new_session_path
    assert_empty cookies[:session_id]
  end

  # Regression: production once crashed on sign-in because `rate_limit` calls
  # `Rails.cache.increment`, and the cache backend wasn't available. Driving the
  # action multiple times asserts the rate-limiting path doesn't blow up.
  test "create stays sane across many sign-in attempts (rate-limiter path)" do
    5.times do
      post session_path, params: { email_address: @user.email_address, password: "wrong" }
      assert_response :redirect
    end
  end
end
