require "test_helper"

class AiChatTest < ActiveSupport::TestCase
  # Test double: overrides the key + per-provider request seams so no network
  # call is ever made. `:raise` simulates a provider erroring (bad key/timeout).
  class FakeChat < AiChat
    def initialize(keys: {}, openai: nil, gemini: nil, routellm: nil)
      super(system: "s", user: "u")
      @keys = keys
      @openai = openai
      @gemini = gemini
      @routellm = routellm
    end

    private

    def key_for(provider) = @keys[provider]
    def openai_request   = @openai == :raise ? raise("openai down") : @openai
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

  test "prefers OpenAI when both keys are present" do
    res = FakeChat.new(keys: { openai: "k", gemini: "g" }, openai: "from-openai", gemini: "from-gemini").call
    assert res.ok?
    assert_equal :openai, res.provider
    assert_equal "from-openai", res.content
  end

  test "fails over from OpenAI to Gemini when OpenAI is unavailable" do
    res = FakeChat.new(keys: { openai: "k", gemini: "g" }, openai: :raise, gemini: "saved").call
    assert res.ok?
    assert_equal :gemini, res.provider
  end

  # Captures the request body instead of touching the network.
  class BodyCapture < AiChat
    attr_reader :bodies

    def initialize(provider, **opts)
      super(system: "s", user: "u" * 50_000, **opts)
      @provider = provider
      @bodies = []
    end

    private

    def key_for(provider) = provider == @provider ? "k" : nil

    def post_json(_uri, body)
      @bodies << body
      { choices: [ { message: { content: "ok" } } ],
        candidates: [ { content: { parts: [ { text: "ok" } ] } } ] }.to_json
    end
  end

  test "every provider request carries an output-token ceiling" do
    openai = BodyCapture.new(:openai, max_tokens: 321)
    assert openai.call.ok?
    assert_equal 321, openai.bodies.first[:max_tokens]

    gemini = BodyCapture.new(:gemini)
    assert gemini.call.ok?
    # Gemini gets extra room for its thinking on top of the answer's ceiling.
    assert_equal AiChat::DEFAULT_MAX_TOKENS + AiChat::GEMINI_THINKING_ROOM, gemini.bodies.first.dig(:generationConfig, :maxOutputTokens)

    routellm = BodyCapture.new(:routellm)
    assert routellm.call.ok?
    assert_equal AiChat::DEFAULT_MAX_TOKENS, routellm.bodies.first[:max_tokens]
  end

  test "the prompt sent to a provider is capped" do
    chat = BodyCapture.new(:openai)
    chat.call
    user_msg = chat.bodies.first[:messages].last[:content]
    assert_equal AiChat::MAX_PROMPT_CHARS, user_msg.length
  end

  test "OpenAI is tried first by default, and AI_PROVIDER_ORDER can change that" do
    assert_equal %i[openai gemini routellm], AiChat.provider_order
    ENV["AI_PROVIDER_ORDER"] = "gemini, openai"
    assert_equal %i[gemini openai routellm], AiChat.provider_order
    ENV["AI_PROVIDER_ORDER"] = "nonsense"
    assert_equal %i[openai gemini routellm], AiChat.provider_order
  ensure
    ENV.delete("AI_PROVIDER_ORDER")
  end
end
