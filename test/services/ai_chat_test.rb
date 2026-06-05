require "test_helper"

class AiChatTest < ActiveSupport::TestCase
  # Test double: overrides the key + per-provider request seams so no network
  # call is ever made. `:raise` simulates a provider erroring (bad key/timeout).
  class FakeChat < AiChat
    def initialize(keys: {}, gemini: nil, routellm: nil)
      super(system: "s", user: "u")
      @keys = keys
      @gemini = gemini
      @routellm = routellm
    end

    private

    def key_for(provider) = @keys[provider]
    def gemini_request   = @gemini == :raise ? raise("gemini down") : @gemini
    def routellm_request = @routellm == :raise ? raise("routellm down") : @routellm
  end

  test "no configured provider short-circuits with :no_key" do
    assert_equal :no_key, FakeChat.new(keys: {}).call.error
  end

  test "uses the first configured provider that succeeds" do
    res = FakeChat.new(keys: { gemini: "k" }, gemini: "answer").call
    assert res.ok?
    assert_equal :gemini, res.provider
    assert_equal "answer", res.content
  end

  test "automatically fails over to the next provider when the first errors" do
    res = FakeChat.new(keys: { gemini: "k1", routellm: "k2" }, gemini: :raise, routellm: "saved").call
    assert res.ok?
    assert_equal :routellm, res.provider
  end

  test "fails over when the first returns blank content" do
    res = FakeChat.new(keys: { gemini: "k1", routellm: "k2" }, gemini: nil, routellm: "ok").call
    assert res.ok?
    assert_equal :routellm, res.provider
  end

  test "every provider failing reports :api" do
    res = FakeChat.new(keys: { gemini: "k1", routellm: "k2" }, gemini: :raise, routellm: :raise).call
    refute res.ok?
    assert_equal :api, res.error
  end
end
