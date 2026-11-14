require "test_helper"

class StudiesIndexTest < ActionDispatch::IntegrationTest
  test "guests get the landing page (no forced login)" do
    get root_path
    assert_response :success
    assert_select ".ps-landing"
    assert_select ".ld-nav"
    assert_select ".ld-feature", minimum: 3
    assert_select ".ld-foot"
  end

  ANDROID_APP = { "User-Agent" => "BiblioRata/1.0.4; NativeBridge; Hotwire Native Android; Turbo Native Android; " \
                                   "Mozilla/5.0 (Linux; Android 16; wv) Chrome/140 Mobile Safari/537.36" }.freeze

  test "the signed-in home greets the reader and has one search box" do
    sign_in_as users(:one)
    get root_path
    assert_response :success
    assert_select ".hm-page"
    assert_select ".hm-hello h1", text: /\AGood (morning|afternoon|evening)/
    assert_select "form.hm-search[action=?][method=get] input[name=q]", search_path
    assert_select ".hm-hello form", count: 1
    assert_select ".hm-verse"
    assert_select ".hm-actions .hm-present[data-action='quick-present#open']"
    assert_select ".hm-actions [data-quick-present-target=status]"
    assert_select ".hm-join", count: 0
  end

  test "an active plan shows its ring, today's passages, one tap to start, and the streak" do
    user = users(:one)
    plan = user.reading_plans.create!(name: "John in 21 days", start_date: Date.current - 2)
    (1..4).each { |n| plan.plan_days.create!(day_number: n, refs: "John #{n}") }
    plan.plan_days.where(day_number: [ 1, 2 ]).each { |d| PlanCompletion.create!(plan_day: d) }
    sign_in_as user
    get root_path
    assert_select ".hm-plan .hm-plan-ring[aria-label=?]", "2 of 4 days read"
    assert_select ".hm-plan .hm-plan-refs", text: /John 3/
    assert_select ".hm-plan a[href=?]", open_today_reading_plan_path(plan), text: /Start today/
    # Today isn't read yet, but yesterday and the day before were.
    assert_select ".hm-streak", text: /2\s+days/
  end

  test "no plan: an invitation to make one, and no streak" do
    sign_in_as users(:one)
    get root_path
    assert_select ".hm-plan.is-empty a[href=?]", new_reading_plan_path
    assert_select ".hm-streak", count: 0
  end

  test "inside the app a signed-out Home tab is the Bible-first home, not the landing page" do
    get root_path, headers: ANDROID_APP
    assert_response :success
    assert_select ".ps-landing", count: 0
    assert_select ".hm-root.is-guest" do
      assert_select ".hm-verse"
      assert_select ".hm-resume[href=?]", read_path, text: /Start reading.*John 3/m
      assert_select ".hm-join a[href=?]", new_registration_path
      assert_select ".hm-join a[href=?]", new_session_path
      assert_select ".hm-actions a[href=?]", search_path
      assert_select ".hm-present", count: 0 # Quick Present needs an account
      assert_select ".hm-studies", count: 0
      assert_select ".hm-plan", count: 0
      assert_select ".hm-streak", count: 0
    end
    assert_select ".hm-hello h1", text: /\AGood (morning|afternoon|evening)\.\z/
  end

  test "an app guest who has been reading picks up their last passage" do
    get read_path, headers: ANDROID_APP # the Bible tab makes the guest's study at John 3
    study = Study.where(user_id: nil).last
    study.panes.first.update!(reference: "Romans 8")
    get root_path, headers: ANDROID_APP
    assert_select ".hm-resume[href=?]", study_path(study), text: /Continue reading.*Romans 8/m
  end

  test "website visitors still get the landing page" do
    get root_path, headers: { "User-Agent" => "Mozilla/5.0 (iPhone) AppleWebKit/605.1.15 Safari/604.1" }
    assert_select ".ps-landing"
    assert_select ".hm-root", count: 0
  end

  test "the home is lean: the same number of queries with 2 studies or 9" do
    user = users(:one)
    2.times { |i| user.studies.create!(name: "S#{i}", pane_count: 2) }
    sign_in_as user
    get root_path # warm caches
    few = count_queries { get root_path }
    7.times { |i| user.studies.create!(name: "T#{i}", pane_count: 2) }
    many = count_queries { get root_path }
    assert_equal few, many, "home queries grow with the number of studies (N+1)"
  end

  test "the welcome shows the quick-open bar, illumined verse and canon stats" do
    get root_path
    assert_select "form.ps-quick-open input[name=?]", "reference"
    assert_select ".ld-vod blockquote"
    assert_select ".ps-canon-stats"
  end

  test "recent studies appear as a shelf of cards for the owner" do
    sign_in_as users(:one)
    users(:one).studies.create!(name: "Romans deep dive", pane_count: 2)
    get root_path
    assert_select ".hm-studies .hm-study .nm", text: "Romans deep dive"
    assert_select ".hm-continue", text: /Continue reading/
  end

  test "quick-open creates a guest study named after the passage with pane I preloaded" do
    assert_difference -> { Study.count }, 1 do
      post studies_path, params: { reference: "John 3:16", pane_count: 2 }
    end
    study = Study.order(:id).last
    assert_redirected_to study_path(study)
    assert_nil study.user_id
    assert_equal "John 3:16", study.name
    assert_equal 2, study.pane_count
    assert_equal "John 3:16", study.panes.first.reference
  end

  test "Compare from the home opens two panes of the same passage" do
    Translation.create!(code: "KJV", name: "King James Version")
    Translation.create!(code: "BSB", name: "Berean Standard Bible")
    post studies_path, params: { reference: "John 3", pane_count: 2 }
    study = Study.order(:id).last
    assert_equal [ "John 3", "John 3" ], study.panes.order(:position).map(&:reference)
  end

  test "quick-open with an unparseable reference still opens a study" do
    post studies_path, params: { reference: "zzz 99", pane_count: 2 }
    study = Study.order(:id).last
    assert_equal "Untitled Study", study.name
    assert_equal "zzz 99", study.panes.first.reference
  end

  private

  def count_queries(&block)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name].in?([ "SCHEMA", "CACHE" ]) || payload[:cached] }
    # The test's shared connection keeps its query cache between requests.
    ActiveRecord::Base.connection.clear_query_cache
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end
end
