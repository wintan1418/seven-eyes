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
