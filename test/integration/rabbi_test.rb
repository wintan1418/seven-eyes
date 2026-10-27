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

  # Swap OpenaiImage.generate for a canned result (same juggling as with_ai_result).
  def with_image_result(result)
    original = OpenaiImage.method(:generate)
    OpenaiImage.singleton_class.define_method(:generate) { |*, **| result }
    yield
  ensure
    OpenaiImage.singleton_class.define_method(:generate, original)
  end

  def member_study
    sign_in_as users(:one)
    users(:one).studies.create!(name: "Sunday", pane_count: 1)
  end

  def quota = IllustrationQuota.for(IllustrationQuota.key_for(users(:one)))

  test "a member can ask the Rabbi and receive a structured exposition" do
    study = member_study

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

  test "a prompt-injected exposition renders as plain text — no link, no script" do
    study = member_study
    json = {
      summary: %(Grace <a href="https://evil.example/login">sign in here</a>.),
      meaning: %(<img src=x onerror="alert(1)">Love wins.), cross_references: []
    }.to_json

    with_ai_result(AiChat::Result.new(ok: true, content: json, provider: :gemini)) do
      get rabbi_study_path(study), params: { verse_id: @v16.id, q: "God so loved" }
    end

    assert_response :success
    assert_includes response.body, "sign in here"
    assert_not_includes response.body, "evil.example"
    assert_select "turbo-frame#rabbi_drawer .ps-rabbi-text a", count: 0
    assert_select "turbo-frame#rabbi_drawer .ps-rabbi-text img", count: 0
    assert_not_includes response.body, "onerror"
  end

  test "guests get a 401 sign-up prompt in the frame and never reach the AI" do
    post studies_path # guest study + session
    study = Study.last

    ai_called = false
    original = AiChat.method(:call)
    AiChat.singleton_class.define_method(:call) { |*, **| ai_called = true }
    begin
      get rabbi_study_path(study), params: { verse_id: @v16.id, q: "God so loved" },
                                   headers: { "Turbo-Frame" => "rabbi_drawer" }
      assert_response :unauthorized
      assert_select "turbo-frame#rabbi_drawer a[href=?]", new_registration_path

      post rabbi_diagram_study_path(study), params: { verse_id: @v16.id }
      assert_response :unauthorized
      assert_select "turbo-frame#rabbi_diagram_frame"

      post rabbi_illustration_study_path(study), params: { verse_id: @v16.id }
      assert_response :unauthorized
      assert_select "turbo-frame#rabbi_illustration_frame"

      get suggest_study_path(study), params: { q: "grace" }
      assert_response :unauthorized
      assert_select "turbo-frame#ai_results"

      get quick_find_study_path(study, q: "jericho"), as: :json
      assert_response :unauthorized
      assert_equal "auth_required", response.parsed_body["error"]

      get prayer_study_path(study), params: { osis: "John", chapter: 3 }, as: :json
      assert_response :unauthorized
    ensure
      AiChat.singleton_class.define_method(:call, original)
    end
    assert_not ai_called, "no paid API call may happen for a guest"
  end

  test "illustrating is POST-only — a GET (Turbo hover-prefetch) must never generate" do
    study = member_study

    get "/studies/#{study.id}/rabbi_illustration?verse_id=#{@v16.id}"
    assert_response :not_found
    get "/studies/#{study.id}/rabbi_diagram?verse_id=#{@v16.id}"
    assert_response :not_found
    assert_equal 0, quota.count
  end

  test "a POST generates an illustration and spends one of today's allowance" do
    study = member_study

    art = AiChat::Result.new(ok: true, provider: :openai, content: {
      illustration: "A father embracing his son", caption: "So loved <b>truly</b>",
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
    assert_includes response.body, "So loved truly"
    assert_equal 1, quota.count
  end

  test "a failed generation hands its reserved slot back" do
    study = member_study

    with_ai_result(AiChat::Result.new(ok: false, error: :api)) do
      post rabbi_illustration_study_path(study), params: { verse_id: @v16.id, q: "God so loved" }
    end

    assert_response :success
    assert_equal 0, quota.count
  end

  test "an exhausted daily allowance renders the quota notice without touching the AI" do
    study = member_study
    quota.update!(count: IllustrationQuota.limit)

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
    study = member_study

    with_ai_result(AiChat::Result.new(ok: false, error: :no_key)) do
      get rabbi_study_path(study), params: { verse_id: @v16.id, q: "God so loved" }
    end

    assert_response :success
    assert_includes response.body, "No AI provider configured"
  end
end
