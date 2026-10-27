require "test_helper"

class AiBudgetTest < ActiveSupport::TestCase
  ENV_KEYS = %w[ AI_DAILY_CHAT_LIMIT AI_USER_DAILY_LIMIT ].freeze

  # The test env uses :null_store; counting needs a real store.
  setup do
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @saved_env = ENV_KEYS.index_with { |k| ENV[k] }
  end

  teardown do
    Rails.cache = @original_cache
    @saved_env.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  test "the global chat budget allows calls up to the ENV limit, then refuses" do
    ENV["AI_DAILY_CHAT_LIMIT"] = "3"
    assert_equal [ true, true, true, false ], 4.times.map { AiBudget.charge(:chat) }
  end

  test "kinds are budgeted independently" do
    ENV["AI_DAILY_CHAT_LIMIT"] = "1"
    assert AiBudget.charge(:chat)
    assert_not AiBudget.charge(:chat)
    assert AiBudget.charge(:image)
  end

  test "the per-user allowance is per user" do
    ENV["AI_USER_DAILY_LIMIT"] = "2"
    assert AiBudget.charge_user(1)
    assert AiBudget.charge_user(1)
    assert_not AiBudget.charge_user(1)
    assert AiBudget.charge_user(2)
  end

  test "a zero limit switches the feature off" do
    ENV["AI_DAILY_CHAT_LIMIT"] = "0"
    assert_not AiBudget.charge(:chat)
  end

  test "AiChat fails soft with :budget once the global cap is spent" do
    ENV["AI_DAILY_CHAT_LIMIT"] = "0"
    chat = AiChat.new(system: "s", user: "u")
    chat.define_singleton_method(:key_for) { |_provider| "test-key" }
    chat.define_singleton_method(:dispatch) { |_provider| raise "must not reach the network" }
    result = chat.call
    assert_not result.ok?
    assert_equal :budget, result.error
  end
end
