require "test_helper"

class RabbiTest < ActionDispatch::IntegrationTest
  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    @rom = Book.create!(osis_code: "Rom", name: "Romans", testament: :new, position: 45, chapter_count: 16)
    @v16 = Verse.create!(translation: @kjv, book: @john, chapter: 3, verse_number: 16, text: "For God so loved the world")
    Verse.create!(translation: @kjv, book: @rom, chapter: 5, verse_number: 8, text: "But God commendeth his love")
  end

  # Swap AiChat.call for a canned result for the duration of the block (no live
  # network call). minitest 6 dropped #stub, so we juggle the singleton method.
  def with_ai_result(result)
    original = AiChat.method(:call)
    AiChat.singleton_class.define_method(:call) { |*, **| result }
    yield
  ensure
    AiChat.singleton_class.define_method(:call, original)
  end

  test "a guest can ask the Rabbi and receive a structured exposition" do
    post studies_path # creates the guest study + sets the session
    study = Study.last

    json = {
      summary: "The plain love of God.", context: "Jesus teaches Nicodemus.",
      meaning: "Belief brings eternal life.", cross_references: [ "Romans 5:8" ],
      caution: "Do not over-read 'world'.", application: "Preach it kindly."
    }.to_json

    with_ai_result(AiChat::Result.new(ok: true, content: json, provider: :gemini)) do
      get rabbi_study_path(study), params: { verse_id: @v16.id, q: "God so loved" }
    end

    assert_response :success
    assert_select "turbo-frame#rabbi_drawer"
    assert_includes response.body, "John 3:16"
    assert_includes response.body, "The plain love of God."
    assert_includes response.body, "Romans 5:8"
  end

  # Swap OpenaiImage.generate for a canned result (same juggling as with_ai_result).
  def with_image_result(result)
    original = OpenaiImage.method(:generate)
    OpenaiImage.singleton_class.define_method(:generate) { |*, **| result }
    yield
  ensure
    OpenaiImage.singleton_class.define_method(:generate, original)
  end

  test "illustrating is POST-only — a GET (Turbo hover-prefetch) must never generate" do
    post studies_path
    study = Study.last

    get "/studies/#{study.id}/rabbi_illustration?verse_id=#{@v16.id}"
    assert_response :not_found
    get "/studies/#{study.id}/rabbi_diagram?verse_id=#{@v16.id}"
    assert_response :not_found
    assert_equal 0, IllustrationQuota.for("g#{study.id}").count
  end

  test "a POST generates an illustration and spends one of today's allowance" do
    post studies_path
    study = Study.last

    art = AiChat::Result.new(ok: true, provider: :openai, content: {
      illustration: "A father embracing his son", caption: "So loved",
      annotations: [ { label: "The embrace", note: "the Father's heart" } ]
    }.to_json)
    image = OpenaiImage::Result.new(ok: true, data_url: "data:image/png;base64,AAAA")

    with_ai_result(art) do
      with_image_result(image) do
        post rabbi_illustration_study_path(study), params: { verse_id: @v16.id, q: "God so loved" }
      end
    end

    assert_response :success
    assert_includes response.body, "data:image/png;base64,AAAA"
    assert_includes response.body, "The embrace"
    assert_equal 1, IllustrationQuota.for("g#{study.id}").count
  end

  test "an exhausted daily allowance renders the quota notice without touching the AI" do
    post studies_path
    study = Study.last
    IllustrationQuota.for("g#{study.id}").update!(count: IllustrationQuota.limit)

    ai_called = false
    with_ai_result(AiChat::Result.new(ok: true, content: "{}")) do
      AiChat.singleton_class.define_method(:call) { |*, **| ai_called = true }
      post rabbi_illustration_study_path(study), params: { verse_id: @v16.id, q: "God so loved" }
    end

    assert_response :success
    assert_includes response.body, "used today&rsquo;s"
    assert_not ai_called, "the image pipeline must not run once the quota is spent"
  end

  test "the Rabbi degrades gracefully when no provider key is set" do
    post studies_path
    study = Study.last

    with_ai_result(AiChat::Result.new(ok: false, error: :no_key)) do
      get rabbi_study_path(study), params: { verse_id: @v16.id, q: "God so loved" }
    end

    assert_response :success
    assert_includes response.body, "No AI provider configured"
  end
end
