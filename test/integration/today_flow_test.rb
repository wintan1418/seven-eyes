require "test_helper"
require_relative "../test_helpers/today_seed"

# Today: the guided daily flow page and marking a day done.
class TodayFlowIntegrationTest < ActionDispatch::IntegrationTest
  include TodaySeed

  ANDROID_APP = { "User-Agent" => "BiblioRata/1.0.5; NativeBridge; Hotwire Native Android; Turbo Native Android; " \
                                   "Mozilla/5.0 (Linux; Android 16; wv) Chrome/140 Mobile Safari/537.36" }.freeze

  setup { seed_today! }

  test "the flow steps through verse, passage, reflection, word, prayer and Amen" do
    sign_in_as users(:one)
    get today_begin_path
    assert_response :success
    assert_select ".tf-root[data-controller=today-flow][data-today-flow-signed-in-value=true]"
    assert_select ".tf-step", 6
    assert_select ".tf-step[data-step]", 6
    assert_equal %w[ verse passage reflection word prayer amen ], css_select(".tf-step").map { |s| s["data-step"] }
    assert_select ".tf-step.is-verse .tf-verse", text: /For with God nothing shall be impossible/
    assert_select ".tf-step.is-verse [data-controller=reader] [data-action='reader#toggle']" # Listen
    assert_select ".tf-step.is-passage .tf-pv.is-focus", text: /For with God/
    assert_select ".tf-step.is-passage .tf-pv", minimum: 5
    assert_select ".tf-step.is-reflection .tf-prose", text: /Nothing you face today/
    assert_select ".tf-step.is-word .tf-term-name", text: "Grace"
    assert_select ".tf-step.is-word .tf-lemma[lang=grc]", text: "χάρις"
    assert_select ".tf-step.is-prayer .tf-prayer", text: /I trust you with today/
    assert_select ".tf-step.is-amen [data-action='today-flow#amen']", text: "Amen"
    assert_select ".tf-progress .tf-seg", 6
    assert_no_match(/Election/, response.body)
  end

  test "guests may walk it too; their streak stays on the device" do
    get today_begin_path
    assert_response :success
    assert_select ".tf-root[data-today-flow-signed-in-value=false]"
    assert_select ".tf-keep a[href=?]", new_registration_path
    assert_select ".tf-hint", text: /on this device/
  end

  test "in the app, the native bar has Back" do
    get today_begin_path, headers: ANDROID_APP
    assert_select "body.hotwire-native .tf-root"
  end

  test "Amen marks today done, idempotently, and returns the streak" do
    user = users(:one)
    user.daily_completions.create!(date: DailyWord.today_date - 1)
    sign_in_as user
    put today_done_path(date: DailyWord.today_date.iso8601), as: :json
    assert_response :success
    assert_equal({ "ok" => true, "date" => DailyWord.today_date.iso8601, "done_today" => true, "streak" => 2 }, response.parsed_body)
    put today_done_path(date: DailyWord.today_date.iso8601), as: :json
    assert_response :success
    assert_equal 2, user.daily_completions.count
  end

  test "a day in the future or long ago is refused (the outbox drops it)" do
    sign_in_as users(:one)
    put today_done_path(date: (DailyWord.today_date + 1).iso8601), as: :json
    assert_response :unprocessable_content
    put today_done_path(date: "2020-01-01"), as: :json
    assert_response :unprocessable_content
    assert_equal 0, DailyCompletion.count
  end

  test "marking a day needs an account" do
    put today_done_path(date: DailyWord.today_date.iso8601), as: :json
    assert_response :redirect
    assert_equal 0, DailyCompletion.count
  end

  test "the home hero offers Begin today, and after Amen says today is done with the streak" do
    user = users(:one)
    sign_in_as user
    get root_path
    assert_select ".hm-today .hm-begin[href=?]", today_begin_path, text: /Begin today.*~5 min/m
    assert_select ".hm-today-open:not([hidden])"
    assert_select ".hm-today-done[hidden]"
    assert_select ".hm-today .il-initial", text: "F"

    DailyCompletion.record!(user, DailyWord.today_date - 1)
    DailyCompletion.record!(user, DailyWord.today_date)
    get root_path
    assert_select ".hm-today.is-done"
    assert_select ".hm-today-open[hidden]"
    assert_select ".hm-today-done:not([hidden])", text: /Today is done.*2-day streak/m
    assert_select ".hm-today-done a", text: /Read the whole chapter/
    assert_select ".hm-today-done [data-action='daily-word#share']", text: /Share today/
    assert_select ".hm-streak[aria-label=?]", "2-day streak"
  end

  test "the service worker keeps the flow for offline use" do
    sw = Rails.root.join("app/javascript/service_worker.js").read
    assert_match %r{/\^\\/today\\/begin\$/}, sw, "OWN_PAGES saves it"
    assert_match %r{CORE_PAGES = \[[^\]]*"/today/begin"}, sw, "warm saves it"
  end
end
