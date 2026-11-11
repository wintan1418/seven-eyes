require "test_helper"

class OpenaiImageRetryTest < ActiveSupport::TestCase
  Response = Struct.new(:code, :body) do
    def is_a?(klass) = klass == Net::HTTPSuccess ? code == "200" : super
  end

  # Records which model each request asked for; the retired one gets OpenAI's 400.
  class FakeImage < OpenaiImage
    attr_reader :asked

    def initialize(prompt) = (super(prompt); @asked = [])

    private

    def api_key = "test-key"

    def post(_uri, json, auth:)
      model = JSON.parse(json)["model"]
      @asked << model
      if model == "gpt-image-1"
        Response.new("400", { error: { message: "The model 'gpt-image-1' does not exist.", param: "model", code: "invalid_value" } }.to_json)
      else
        Response.new("200", { data: [ { b64_json: "QUJD" } ] }.to_json)
      end
    end
  end

  setup do
    @saved = ENV["OPENAI_IMAGE_MODEL"]
    ENV["OPENAI_IMAGE_MODEL"] = "gpt-image-1" # the retired model, as set before
    @real_fetch = AiModels.method(:fetch)
    AiModels.define_singleton_method(:fetch) { |_provider, _key| %w[gpt-4o gpt-image-2 gpt-image-2-mini] }
    AiModels.refresh!(:openai)
  end

  teardown do
    ENV["OPENAI_IMAGE_MODEL"] = @saved
    AiModels.define_singleton_method(:fetch, @real_fetch)
    AiModels.singleton_class.send(:private, :fetch)
    AiModels.refresh!(:openai)
  end

  test "a retired image model is swapped for the current one and the picture still comes back" do
    image = FakeImage.new("a shepherd on a hillside")
    result = image.generate
    assert result.ok?, "expected an image, got #{result.error.inspect}"
    assert_equal "data:image/png;base64,QUJD", result.data_url
    assert_equal %w[gpt-image-1 gpt-image-2], image.asked
  end

  test "with no override it asks for the newest model straight away" do
    ENV.delete("OPENAI_IMAGE_MODEL")
    image = FakeImage.new("a lamp on a stand")
    assert image.generate.ok?
    assert_equal %w[gpt-image-2], image.asked
  end
end
