require "test_helper"

class RabbiIllustrationTest < ActiveSupport::TestCase
  # Test double: overrides both network seams (art-direction chat + image gen)
  # so no live API call is made.
  class FakeIllustration < RabbiIllustration
    def initialize(verse:, study:, selection: nil, verses: nil, art: nil, image: nil)
      super(verse:, study:, selection:, verses:)
      @art = art
      @image = image
    end

    private

    def art_direction = @art
    def generate_image(_prompt) = @image
  end

  def fake_art(content) = AiChat::Result.new(ok: true, content: content, provider: :openai)
  def fake_image = OpenaiImage::Result.new(ok: true, data_url: "data:image/png;base64,AAAA")

  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @exod = Book.create!(osis_code: "Exod", name: "Exodus", testament: :old, position: 2, chapter_count: 40)
    @v10 = Verse.create!(translation: @kjv, book: @exod, chapter: 25, verse_number: 10, text: "And they shall make an ark...")
    @study = Study.create!(name: "Test study", pane_count: 1)
  end

  test "missing verse reports :no_verse without any AI call" do
    assert_equal :no_verse, FakeIllustration.new(verse: nil, study: @study).call.error
  end

  test "an unconfigured provider surfaces :no_key" do
    art = AiChat::Result.new(ok: false, error: :no_key)
    assert_equal :no_key, FakeIllustration.new(verse: @v10, study: @study, art:).call.error
  end

  test "an empty scene reports :none and never calls the image model" do
    art = fake_art({ illustration: "", caption: "" }.to_json)
    r = FakeIllustration.new(verse: @v10, study: @study, art:, image: nil).call
    assert_equal :none, r.error
  end

  test "a described scene renders an image data URL with its caption" do
    art = fake_art({ illustration: "The golden ark under a tent", caption: "The Ark" }.to_json)
    r = FakeIllustration.new(verse: @v10, study: @study, selection: "make an ark", art:, image: fake_image).call
    assert r.ok?
    assert_equal "The Ark", r.caption
    assert_match %r{\Adata:image/png;base64,}, r.image
    assert_equal "Exodus 25:10", r.origin
    assert_equal :openai, r.provider
  end

  test "a failed image generation surfaces the image error" do
    art = fake_art({ illustration: "a scene", caption: "c" }.to_json)
    img = OpenaiImage::Result.new(ok: false, error: :api)
    assert_equal :api, FakeIllustration.new(verse: @v10, study: @study, art:, image: img).call.error
  end
end
