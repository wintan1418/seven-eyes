require "test_helper"

# Quick Find / the Rabbi / illustrations answer at once with a "thinking"
# state; AiRequestJob does the model call; the page polls studies#ai_request.
class AiRequestsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    @v16 = Verse.create!(translation: @kjv, book: @john, chapter: 3, verse_number: 16, text: "For God so loved the world")
    sign_in_as users(:one)
    @study = users(:one).studies.create!(name: "Sunday", pane_count: 1)
    @calls = 0
    @original_search = PulpitSearch.method(:call)
  end

  teardown do
    PulpitSearch.define_singleton_method(:call, @original_search)
  end

  def stub_search(&block)
    test = self
    PulpitSearch.define_singleton_method(:call) do |*args, **kw|
      test.instance_variable_set(:@calls, test.instance_variable_get(:@calls) + 1)
      block.call(*args, **kw)
    end
  end

  def jericho
    PulpitSearch::Result.new(ok: true, topic: "Jericho", summary: "The walls fell.",
      suggestions: [ PulpitSearch::Suggestion.new(reference: "John 3:16", osis: "John", chapter: 3, verse_start: 16, verse_end: 16, preview: "For God") ])
  end

  def quota = IllustrationQuota.for(IllustrationQuota.key_for(users(:one)))

  # ---- Quick Find ------------------------------------------------------------

  test "quick find returns at once with a poll URL; the AI runs only in the job" do
    stub_search { jericho }

    assert_enqueued_with(job: AiRequestJob) do
      get quick_find_study_path(@study, q: "walls of jericho"), as: :json
    end
    assert_response :accepted
    body = response.parsed_body
    assert body["pending"]
    assert_equal 0, @calls, "the web request must not call the AI"

    get body["poll_url"], as: :json
    assert_response :accepted
    assert_equal "pending", response.parsed_body["status"]

    perform_enqueued_jobs
    assert_equal 1, @calls

    get body["poll_url"], as: :json
    assert_response :success
    data = response.parsed_body
    assert data["ok"]
    assert_equal "done", data["status"]
    assert_equal "Jericho", data["topic"]
    assert_equal "John 3", data["suggestions"].first["chapter_reference"]
  end

  test "an identical question still thinking is not asked twice" do
    stub_search { jericho }
    get quick_find_study_path(@study, q: "jericho"), as: :json
    first = response.parsed_body["poll_url"]
    get quick_find_study_path(@study, q: "jericho"), as: :json
    assert_equal first, response.parsed_body["poll_url"]
    assert_enqueued_jobs 1, only: AiRequestJob
  end

  test "a crashed AI call reports a failure; asking again works" do
    stub_search { raise "provider exploded" }
    perform_enqueued_jobs { get quick_find_study_path(@study, q: "jericho"), as: :json }
    get response.parsed_body["poll_url"], as: :json
    assert_response :success
    assert_equal({ "ok" => false, "error" => "api", "status" => "failed" }, response.parsed_body)

    stub_search { jericho }
    perform_enqueued_jobs { get quick_find_study_path(@study, q: "jericho"), as: :json }
    get response.parsed_body["poll_url"], as: :json
    assert response.parsed_body["ok"]
  end

  test "a question the worker never picked up times out instead of spinning forever" do
    get quick_find_study_path(@study, q: "jericho"), as: :json
    url = response.parsed_body["poll_url"]
    AiRequest.last.update_columns(created_at: (AiRequest::STALE_AFTER + 1.minute).ago)

    get url, as: :json
    assert_equal "timeout", response.parsed_body["error"]
    assert AiRequest.last.failed?
  end

  # ---- who may read an answer ------------------------------------------------

  test "only the asker, on their own study, can read the answer" do
    stub_search { jericho }
    perform_enqueued_jobs { get quick_find_study_path(@study, q: "jericho"), as: :json }
    token = AiRequest.last.token

    other_study = users(:one).studies.create!(name: "Other", pane_count: 1)
    get ai_request_study_path(other_study, token:), as: :json
    assert_response :not_found

    get ai_request_study_path(@study, token: "not-the-token"), as: :json
    assert_response :not_found

    sign_out
    sign_in_as users(:two)
    get ai_request_study_path(@study, token:), as: :json
    assert_response :not_found # not their study

    users(:two).studies.create!(name: "Theirs", pane_count: 1)
    AiRequest.last.update_columns(study_id: users(:two).studies.last.id)
    get ai_request_study_path(users(:two).studies.last, token:), as: :json
    assert_response :not_found # their study, but not their question
  end

  test "a guest (session-scoped study) cannot poll at all" do
    sign_out
    post studies_path
    guest_study = Study.last
    get ai_request_study_path(guest_study, token: "anything"), as: :json
    assert_response :unauthorized
  end

  # ---- the Rabbi ---------------------------------------------------------------

  test "a cached Rabbi answer renders at once without queueing" do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    exposition = RabbiExposition.new(verse: @v16, verses: [ @v16 ], selection: "God so loved", study: @study)
    Rails.cache.write(exposition.cache_key, { data: { "summary" => "Cached love." }, provider: :gemini })

    assert_no_enqueued_jobs(only: AiRequestJob) do
      get rabbi_study_path(@study), params: { verse_id: @v16.id, q: "God so loved" }
    end
    assert_response :success
    assert_includes response.body, "Cached love."
  ensure
    Rails.cache = original_cache
  end

  test "a Rabbi answer that timed out shows Try again" do
    get rabbi_study_path(@study), params: { verse_id: @v16.id, q: "God so loved" }
    url = css_select("[data-rabbi-target=pending]").first["data-url"]
    assert_includes response.body, "The Rabbi is reading the whole chapter"
    AiRequest.last.update_columns(created_at: 10.minutes.ago)

    get url
    assert_response :success
    assert_select "turbo-frame#rabbi_drawer [role=alert]", text: /took too long/
    assert_select "turbo-frame#rabbi_drawer button[data-action='rabbi#retry']", text: "Try again"
  end

  # ---- illustrations -----------------------------------------------------------

  test "an illustration holds its slot while painting and gets it back on timeout" do
    post rabbi_illustration_study_path(@study), params: { verse_id: @v16.id, q: "God so loved", style: "labeled" }
    assert_response :success
    pending = css_select("turbo-frame#rabbi_illustration_frame [data-rabbi-target=pending]").first
    assert pending
    assert_equal rabbi_illustration_study_path(@study, verse_id: @v16.id, verse_ids: @v16.id.to_s, q: "God so loved", style: "labeled"),
                 pending["data-retry-url"]
    assert_equal 1, quota.count
    assert_equal "labeled", AiRequest.last.params["style"]

    AiRequest.last.update_columns(created_at: 10.minutes.ago)
    get pending["data-url"]
    assert_select "[role=alert]", text: /took too long/
    assert_equal 0, quota.count
  end

  test "each illustration click reserves its own slot (never de-duplicated)" do
    2.times { post rabbi_illustration_study_path(@study), params: { verse_id: @v16.id, q: "God so loved" } }
    assert_enqueued_jobs 2, only: AiRequestJob
    assert_equal 2, quota.count
  end
end
