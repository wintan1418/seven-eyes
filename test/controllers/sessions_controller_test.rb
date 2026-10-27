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

  test "signing in resets the Rails session (no fixation) but keeps the guest study" do
    post studies_path # guest study lives in the session
    guest_study = Study.last
    assert_nil guest_study.user_id
    before = session.id.to_s

    post session_path, params: { email_address: @user.email_address, password: "password" }

    assert_not_equal before, session.id.to_s, "a fresh session id is issued on sign-in"
    assert_redirected_to study_path(guest_study)
    assert_equal @user.id, guest_study.reload.user_id
  end

  test "a session older than the TTL no longer authenticates and is removed" do
    sign_in_as(@user)
    Current.session.update_column(:created_at, (Session::TTL + 1.day).ago)
    stale_id = Current.session.id

    get admin_path # any authenticated-only page
    assert_redirected_to new_session_path
    assert_not Session.exists?(stale_id)
  end

  test "a fresh session still authenticates" do
    sign_in_as(@user)
    get root_path
    assert_response :success
    assert_select "form[action=?]", session_path # signed-in workspace shows Sign out
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
