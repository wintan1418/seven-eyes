require "test_helper"

# The per-user daily AI allowance (AiBudget) on the AI endpoints. (The
# per-minute `rate_limit` uses the controller's cache store, which is
# :null_store in test, so it's exercised in production only; Rack::Attack's
# IP throttles are covered in rack_attack_test.rb.)
class AiLimitsTest < ActionDispatch::IntegrationTest
  setup do
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @saved_limit = ENV["AI_USER_DAILY_LIMIT"]
    ENV["AI_USER_DAILY_LIMIT"] = "2"

    sign_in_as users(:one)
    @study = users(:one).studies.create!(name: "S", pane_count: 1)
    @original_call = ScriptureSuggester.method(:call)
    ScriptureSuggester.define_singleton_method(:call) { |*_a, **_k| ScriptureSuggester::Result.new(ok: true, suggestions: []) }
  end

  teardown do
    ScriptureSuggester.define_singleton_method(:call, @original_call)
    Rails.cache = @original_cache
    @saved_limit.nil? ? ENV.delete("AI_USER_DAILY_LIMIT") : ENV["AI_USER_DAILY_LIMIT"] = @saved_limit
  end

  test "a member past today's AI allowance gets a 429 in the frame" do
    2.times do
      get suggest_study_path(@study), params: { q: "grace" }
      assert_response :success
    end

    get suggest_study_path(@study), params: { q: "grace" }
    assert_response :too_many_requests
    assert_select "turbo-frame#ai_results", text: /today’s AI allowance/
  end

  test "JSON callers get a JSON 429" do
    2.times { get suggest_study_path(@study), params: { q: "grace" } }
    get quick_find_study_path(@study, q: "jericho"), as: :json
    assert_response :too_many_requests
    assert_equal "daily_limit", response.parsed_body["error"]
  end

  test "an over-long query is truncated before it reaches the model" do
    seen = nil
    ScriptureSuggester.define_singleton_method(:call) do |q, **|
      seen = q
      ScriptureSuggester::Result.new(ok: true, suggestions: [])
    end
    get suggest_study_path(@study), params: { q: "x" * 5_000 }
    assert_response :success
    assert_equal StudiesController::AI_QUERY_LIMIT, seen.length
  end
end
