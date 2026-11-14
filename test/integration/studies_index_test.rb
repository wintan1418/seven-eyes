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
    assert_select ".hm-root[data-daypart]"
    assert_select ".hm-today-hello", text: /\AGood (morning|afternoon|evening)/
    assert_select "form.hm-search[action=?][method=get] input[name=q]", search_path
    assert_select "form.hm-search", count: 1
    assert_select ".hm-today"
    assert_select ".hm-today .hm-begin[href=?]", today_begin_path
    assert_select ".hm-actions .hm-present[data-action='quick-present#open']"
    assert_select ".hm-actions [data-quick-present-target=status]"
    assert_select ".hm-join", count: 0
    assert_select ".il-heading-title", text: /Continue/
  end

  test "?at= stands in for the clock outside production: dawn, midday, evening" do
    sign_in_as users(:one)
    { "06:30" => [ "dawn", "Good morning" ], "13:00" => [ "day", "Good afternoon" ], "20:15" => [ "evening", "Good evening" ] }.each do |at, (part, hello)|
      get root_path(at:)
      assert_select ".hm-root[data-daypart=?]", part
      assert_select ".hm-today-hello", text: /\A#{hello}/
      assert_select "[data-today-hero-fixed-value=true]"
    end
  end

  test "an active plan shows its ring and today's passages in the Continue rail" do
    user = users(:one)
    plan = user.reading_plans.create!(name: "John in 21 days", start_date: Date.current - 2)
    (1..4).each { |n| plan.plan_days.create!(day_number: n, refs: "John #{n}") }
    plan.plan_days.where(day_number: [ 1, 2 ]).each { |d| PlanCompletion.create!(plan_day: d) }
    sign_in_as user
    get root_path
    assert_select ".hm-rail .hm-plan[href=?]", open_today_reading_plan_path(plan) do
      assert_select ".hm-plan-ring[aria-label=?]", "2 of 4 days read"
      assert_select ".hm-rail-meta", text: /John 3/
      assert_select ".hm-rail-foot", text: /2-day plan streak/
    end
  end

  test "no plan: the For you card offers one, started in one tap" do
    Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    user = users(:one)
    sign_in_as user
    get root_path
    assert_select ".hm-rail .hm-plan", count: 0
    assert_select ".hm-foryou form.hm-fy-card.is-plan[action=?]", reading_plans_path do
      assert_select "input[name='reading_plan[template]'][value=book]"
    end
  end

  test "inside the app a signed-out Home tab is the Bible-first home, not the landing page" do
    get root_path, headers: ANDROID_APP
    assert_response :success
    assert_select ".ps-landing", count: 0
    assert_select ".hm-root.is-guest" do
      assert_select ".hm-today .hm-begin[href=?]", today_begin_path
      assert_select ".hm-resume[href=?]", read_path, text: /Start reading.*John 3/m
      assert_select ".hm-join a[href=?]", new_registration_path
      assert_select ".hm-join a[href=?]", new_session_path
      assert_select ".hm-actions a[href=?]", search_path
      assert_select ".hm-present", count: 0 # Quick Present needs an account
      assert_select ".hm-studies", count: 0
      assert_select ".hm-rail .hm-plan", count: 0
      assert_select ".hm-foryou", count: 0
      assert_select ".hm-sunday", count: 0
      assert_select ".hm-streak[hidden]"
      assert_select ".hm-done-keep a[href=?]", new_registration_path # keep your streak
    end
    assert_select ".hm-today-hello", text: /\AGood (morning|afternoon|evening)\.\z/
  end

  test "an app guest who has been reading picks up their last passage" do
    get read_path, headers: ANDROID_APP # the Bible tab makes the guest's study at John 3
    study = Study.where(user_id: nil).last
    study.panes.first.update!(reference: "Romans 8")
    get root_path, headers: ANDROID_APP
    assert_select ".hm-resume[href=?]", study_path(study), text: /Continue reading.*Romans 8/m
    assert_select ".hm-resume progress.hm-bar[value='8'][max='16']"
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

  test "the home stays lean with everything on: a plan, a streak, pastor mode and a long queue" do
    Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    user = users(:one)
    plan = user.reading_plans.create!(name: "John", start_date: Date.current - 1)
    (1..3).each { |n| plan.plan_days.create!(day_number: n, refs: "John #{n}") }
    3.times { |n| user.daily_completions.create!(date: DailyWord.today_date - n) }
    service = user.studies.create!(name: "Sunday", pane_count: 1, last_opened_at: Time.current)
    service.panes.first.update!(reference: "John 3")
    2.times { |n| service.setlist_items.create!(kind: :scripture, reference: "John #{n + 1}:1") }
    sign_in_as user
    get root_path
    few = count_queries { get root_path }
    8.times { |n| service.setlist_items.create!(kind: :song, title: "Song #{n}", body: "Words") }
    6.times { |i| user.studies.create!(name: "T#{i}", pane_count: 1, last_opened_at: (i + 1).hours.ago).panes.first.update!(reference: "John #{i + 1}") }
    many = count_queries { get root_path }
    assert_equal few, many, "home queries grow with queue items or studies (N+1)"
    assert_operator many, :<=, 40, "the home makes #{many} queries"
  end

  test "the welcome shows the quick-open bar, illumined verse and canon stats" do
    get root_path
    assert_select "form.ps-quick-open input[name=?]", "reference"
    assert_select ".ld-vod blockquote"
    assert_select ".ps-canon-stats"
  end

  test "recent studies appear as a shelf of cards for the owner" do
    sign_in_as users(:one)
    users(:one).studies.create!(name: "Romans deep dive", pane_count: 2, last_opened_at: 10.days.ago)
    4.times { |i| users(:one).studies.create!(name: "Recent #{i}", pane_count: 1, last_opened_at: i.hours.ago) }
    get root_path
    assert_select ".hm-studies .hm-study .nm", text: "Romans deep dive"
    assert_select ".hm-continue-block .hm-rail", text: /Continue reading|Start reading/
  end

  test "a study in the Continue rail isn't repeated under the studies list" do
    sign_in_as users(:one)
    users(:one).studies.where(quick_present: false).destroy_all
    6.times { |i| users(:one).studies.create!(name: "Study #{i}", pane_count: 1, last_opened_at: i.hours.ago) }
    get root_path
    rail = css_select(".hm-continue-block .hm-rail-title").map { |n| n.text.strip }
    listed = css_select(".hm-studies .hm-study .nm").map { |n| n.text.strip }
    assert_equal [ "Study 4", "Study 5" ], listed
    %w[ 1 2 3 ].each { |i| assert_includes rail, "Study #{i}" }
    assert_empty listed & rail
    assert_select ".hm-studies .il-heading-title", text: /More studies/
  end

  test "when the rail holds every study, the list points to the menu instead of repeating them" do
    sign_in_as users(:one)
    users(:one).studies.where(quick_present: false).destroy_all
    2.times { |i| users(:one).studies.create!(name: "Only #{i}", pane_count: 1, last_opened_at: i.hours.ago) }
    get root_path
    assert_select ".hm-studies .hm-study", count: 0
    assert_select ".hm-studies button[data-sheets-id-param='menu']", text: /All your studies/
  end

  test "readers' testimonials get an illuminated slider on Home, and none means no section" do
    sign_in_as users(:one)
    get root_path
    assert_select ".hm-voices", count: 0

    3.times do |i|
      Testimonials::Testimonial.create!(kind: "text", status: "approved", source: "page", consent_given: true,
                                        name: "Reader #{i}", body: "It helps me prepare. #{i}")
    end
    get root_path
    assert_select ".hm-voices .il-heading-title", text: /From fellow readers/
    assert_select ".hm-voices-slider[data-controller='shatter-slider'] .hm-voices-track[data-shatter-slider-target='track']"
    assert_select ".hm-voice[data-shatter-slider-target='slide']", 3
    assert_select ".hm-voice .hm-voice-mark", 3
    assert_select ".hm-voices a[href='/testimonials/new']", text: /Share how BiblioRata helps you/
    html = response.body
    assert_operator html.index("hm-voices"), :<, html.index("hm-studies"), "testimonials come before the studies"
  end

  test "an app guest's Home has the testimonials too" do
    Testimonials::Testimonial.create!(kind: "text", status: "approved", source: "page", consent_given: true,
                                      name: "Ada", body: "Helps every Sunday.")
    get root_path, headers: { "User-Agent" => "BiblioRata/1.0.5; NativeBridge; Hotwire Native Android; Turbo Native Android; Mozilla/5.0" }
    assert_select ".hm-root.is-guest"
    assert_select ".hm-voice", text: /Helps every Sunday/
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
