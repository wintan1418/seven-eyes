require "test_helper"

class AiRequestJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @study = @user.studies.create!(name: "S", pane_count: 1)
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    @v16 = Verse.create!(translation: @kjv, book: @john, chapter: 3, verse_number: 16, text: "For God so loved the world")
    @original_chat = AiChat.method(:call)
    @original_image = OpenaiImage.method(:generate)
  end

  teardown do
    AiChat.singleton_class.define_method(:call, @original_chat)
    OpenaiImage.singleton_class.define_method(:generate, @original_image)
  end

  def chat(result) = AiChat.singleton_class.define_method(:call) { |*, **| result }

  test "runs on the ai queue and is never retried" do
    assert_equal "ai", AiRequestJob.new.queue_name
  end

  test "a Rabbi answer is stored as plain data and rebuilds into the partial's Result" do
    chat AiChat::Result.new(ok: true, provider: :gemini,
                            content: { summary: "Love <b>given</b>.", cross_references: [ "John 3:16" ] }.to_json)
    req = AiRequest.create!(user: @user, study: @study, kind: "rabbi", params: { q: "God so loved", verse_ids: [ @v16.id ] })

    AiRequestJob.perform_now(req.id)

    req.reload
    assert req.done?
    result = AiWork.rabbi_result(req.result)
    assert result.ok?
    assert_equal "Love given.", result.exposition.summary
    assert_equal :gemini, result.provider
    assert_kind_of RabbiExposition::CrossRef, result.cross_references.first
  end

  test "an illustration that fails gives its slot back" do
    quota = IllustrationQuota.for(IllustrationQuota.key_for(@user))
    quota.reserve!
    chat AiChat::Result.new(ok: true, provider: :openai, content: { illustration: "A hill", annotations: [] }.to_json)
    OpenaiImage.singleton_class.define_method(:generate) { |*, **| OpenaiImage::Result.new(ok: false, error: :api) }
    req = AiRequest.create!(user: @user, study: @study, kind: "rabbi_illustration",
                            params: { q: "x", verse_ids: [ @v16.id ], style: "realistic" }, illustration_quota_id: quota.id)

    AiRequestJob.perform_now(req.id)

    assert req.reload.done?
    assert_equal :api, AiWork.illustration_result(req.result).error
    assert_equal 0, quota.reload.count
  end

  test "a crash is recorded as a failure, not raised" do
    AiChat.singleton_class.define_method(:call) { |*, **| raise "boom" }
    original = AiWork.method(:run)
    AiWork.define_singleton_method(:run) { |*| raise "boom" }
    req = AiRequest.create!(user: @user, study: @study, kind: "quick_find", params: { q: "grace" })
    AiRequestJob.perform_now(req.id)
    assert req.reload.failed?
    assert_equal "api", req.error
  ensure
    AiWork.define_singleton_method(:run, original) if original
  end

  test "a finished or missing request is left alone" do
    req = AiRequest.create!(user: @user, study: @study, kind: "quick_find", params: { q: "grace" }, status: "done", result: { "ok" => true })
    AiRequestJob.perform_now(req.id)
    assert_equal({ "ok" => true }, req.reload.result)
    assert_nothing_raised { AiRequestJob.perform_now(0) }
  end
end
