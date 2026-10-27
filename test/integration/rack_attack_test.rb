require "test_helper"

class RackAttackTest < ActionDispatch::IntegrationTest
  # Rack::Attack counts in Rails.cache, which is :null_store in test — give it a
  # real store for these tests only.
  setup do
    @original_store = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    # Throttles count per time window; pin the clock so a test never straddles
    # a window boundary (that made this flaky in CI).
    travel_to Time.utc(2026, 1, 1, 12, 0, 30)
  end

  teardown do
    Rack::Attack.cache.store = @original_store
  end

  test "sign-in attempts from one IP are throttled" do
    20.times do |i|
      post session_path, params: { email_address: "nobody#{i}@example.com", password: "x" }
      assert_response :redirect
    end
    post session_path, params: { email_address: "other@example.com", password: "x" }
    assert_response :too_many_requests
    assert response.headers["retry-after"].present?
  end

  test "password reset requests for one email are throttled" do
    3.times do
      post passwords_path, params: { email_address: "one@example.com" }
      assert_response :redirect
    end
    post passwords_path, params: { email_address: "ONE@example.com " }
    assert_response :too_many_requests
  end

  test "the AI endpoints are throttled per IP" do
    40.times { get "/studies/0/quick_find", params: { q: "x" } }
    get "/studies/0/quick_find", params: { q: "x" }
    assert_response :too_many_requests
  end

  test "ordinary reading is never throttled" do
    50.times { get root_path }
    assert_response :success
  end
end
