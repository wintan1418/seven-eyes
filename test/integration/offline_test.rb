require "test_helper"

class OfflineTest < ActionDispatch::IntegrationTest
  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    Translation.create!(code: "NET", name: "NET Bible")
    john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    @verse = Verse.create!(translation: @kjv, book: john, chapter: 3, verse_number: 16, text: "For God so loved the world")
  end


  test "the Offline Bibles page lists downloadable Bibles, never restricted ones" do
    get offline_path
    assert_response :success
    assert_select ".ui-offline-row[data-code='KJV']"
    assert_select ".ui-offline-row[data-code='NET']", 0
    assert_select "[data-controller~='offline-downloads']"
  end

  test "the manifest has sizes, versioned URLs, books, aliases and pane icons" do
    get offline_bibles_path
    assert_response :success
    assert_equal "no-cache", response.headers["Cache-Control"]
    data = response.parsed_body
    assert_equal [ "KJV" ], data["translations"].map { |t| t["code"] }
    kjv = data["translations"].first
    assert_match %r{\A/offline/bibles/KJV\?v=[0-9a-f]{16}\z}, kjv["url"]
    assert_equal "John", data["books"].first["osis"]
    assert_includes data["canon"].find { |b| b["osis"] == "John" }["aliases"], "jn"
    assert_match(/<svg class="ui-icon"/, data["icons"]["chevron_right"])
  end

  test "a bundle is served gzipped with a long cache on its versioned URL and answers ETag re-checks" do
    get offline_bibles_path
    url = response.parsed_body["translations"].first["url"]

    get url, headers: { "Accept-Encoding" => "gzip" }
    assert_response :success
    assert_equal "gzip", response.headers["Content-Encoding"]
    assert_match(/max-age=\d{8}/, response.headers["Cache-Control"]) # a year
    assert_match(/immutable/, response.headers["Cache-Control"])
    body = JSON.parse(ActiveSupport::Gzip.decompress(response.body))
    assert_equal "KJV", body["code"]
    assert_equal [ "For God so loved the world" ], body["books"].first["chapters"][2]["t"].compact.then { |t| t.empty? ? body["books"].first["chapters"].compact.first["t"] : t }

    etag = response.headers["ETag"]
    get url, headers: { "Accept-Encoding" => "gzip", "If-None-Match" => etag }
    assert_response :not_modified
  end

  test "without gzip support the bundle is plain JSON" do
    get offline_bible_path("kjv")
    assert_response :success
    assert_nil response.headers["Content-Encoding"]
    assert_equal "KJV", response.parsed_body["code"]
  end

  test "restricted and unknown translations are not served" do
    get offline_bible_path("NET")
    assert_response :not_found
    get offline_bible_path("NOPE")
    assert_response :not_found
  end

  test "highlights are the signed-in reader's own, never a guest's" do
    get offline_highlights_path
    assert_response :unauthorized

    user = users(:one)
    sign_in_as user
    mine = user.highlights.create!(verse: @verse, color: :sage, char_start: 0, char_end: 3, note: "love")
    users(:two).highlights.create!(verse: @verse, color: :rose, char_start: 4, char_end: 7)
    get offline_highlights_path
    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal [ { "id" => mine.id, "verse_id" => @verse.id, "char_start" => 0, "char_end" => 3, "color" => "sage", "note" => "love" } ],
                 response.parsed_body["highlights"]
  end

  test "every page tells the offline layer who the data belongs to" do
    get offline_path
    assert_select "body[data-offline-owner='guest']"
    sign_in_as users(:one)
    get offline_path
    owner = css_select("body").first["data-offline-owner"]
    assert_match(/\Au-[0-9a-f]{16}\z/, owner)
    assert_not_includes owner, users(:one).id.to_s
  end
end

class OfflinePlansPageTest < ActionDispatch::IntegrationTest
  test "plan days carry their date, and the coming week its passages, for offline use" do
    user = users(:one)
    sign_in_as user
    study = user.studies.create!(name: "Plan", pane_count: 1)
    plan = user.reading_plans.create!(name: "Gospel", start_date: Date.current, study:)
    plan.plan_days.create!(day_number: 1, refs: "Genesis 1, Genesis 2, Genesis 3, Psalm 1, Matt 1, Mark 1")
    plan.plan_days.create!(day_number: 30, refs: "John 1")

    get reading_plan_path(plan)
    assert_select "[data-controller~='plan-offline'][data-plan-offline-study-url-value='#{study_path(study)}']"
    assert_select "turbo-frame[data-date='#{Date.current.iso8601}'][data-pane-refs='Genesis 1-3|Psalm 1|Matt 1|Mark 1']"
    far = css_select("turbo-frame[data-date='#{(Date.current + 29).iso8601}']").first
    assert_nil far["data-pane-refs"], "only the coming week's passages are listed"
    assert_select "a[data-action~='plan-offline#begin']"
  end
end
