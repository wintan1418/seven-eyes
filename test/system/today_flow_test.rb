require "application_system_test_case"
require_relative "../test_helpers/today_seed"

# Today, end to end: Begin today on Home → the verse, the passage, the
# reflection, the word of the faith, the prayer → Amen → the seal, the day
# marked done (server for an account, the device for a guest) and Home's
# hero saying so with the streak. Also: pausing part-way, the app guest, and
# finishing with no signal (the outbox sends it later).
class TodayFlowSystemTest < ApplicationSystemTestCase
  include TodaySeed

  APP_UA = "BiblioRata/1.0.5; NativeBridge; Hotwire Native Android; Turbo Native Android; " \
           "Mozilla/5.0 (Linux; Android 16; wv) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Mobile Safari/537.36"

  setup do
    seed_today!
    users(:one).daily_completions.create!(date: DailyWord.today_date - 1)
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.driver.browser.execute_cdp("Network.setUserAgentOverride", userAgent: "")
  end

  test "on a phone: Begin today → every step → Amen → today is done and the streak grows" do
    phone
    sign_in
    within(".hm-today") { click_on "Begin today" }

    assert_selector ".tf-count", text: "1 of 6"
    assert_selector ".tf-step.is-verse .tf-verse", text: "For with God nothing shall be impossible", visible: true
    assert_selector "button.tf-listen[aria-label='Listen to the verse']"
    no_overflow = page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
    assert no_overflow, "the flow fits the phone"

    click_on "Next"
    assert_selector ".tf-count", text: "2 of 6"
    assert_selector ".tf-pv.is-focus", text: "For with God", visible: true
    click_on "Back"
    assert_selector ".tf-count", text: "1 of 6"
    3.times { click_on "Next" }
    assert_selector ".tf-count", text: "4 of 6"
    assert_selector ".tf-term-name", text: "Grace", visible: true
    assert_selector ".tf-lemma", text: "χάρις", visible: true
    click_on "Next"
    assert_selector ".tf-prayer", text: "I trust you with today", visible: true
    click_on "Finish"
    assert_selector ".tf-count", text: "6 of 6"

    # The seal is a drawn gilt cross in a ring (not a font glyph); after Amen the streak takes its place.
    assert_selector "svg.tf-seal-mark[role='img'][aria-label='Amen seal: a gilded cross']", visible: true
    click_on "Amen"
    assert_selector ".tf-amen-title", text: "Today is done"
    assert_selector ".tf-amen-streak", text: "2 days in a row."
    assert_selector ".tf-root.is-complete"
    assert_selector ".tf-seal-num", text: "2", visible: true
    assert_no_selector "svg.tf-seal-mark", visible: true
    Timeout.timeout(5) { sleep 0.1 until DailyCompletion.done_on?(users(:one)) }

    click_on "Back to Home"
    assert_selector ".hm-today.is-done"
    assert_selector ".hm-today-done", text: /Today is done.*2-day streak/m
    assert_link "Read the whole chapter"
    assert_no_link "Begin today"
    assert_selector ".hm-streak b", text: "2"
  end

  test "pausing part-way: Home offers to pick up where you paused" do
    sign_in
    visit today_begin_path
    2.times { click_on "Next" }
    assert_selector ".tf-count", text: "3 of 6"
    visit root_path
    assert_selector ".hm-rail-card.is-today", text: /Pick up where you paused.*Step 3 of 6/m
    find(".hm-rail-card.is-today").click
    assert_selector ".tf-count", text: "3 of 6"
    assert_selector ".tf-prose", text: "Nothing you face today", visible: true
  end

  test "the app guest: the Bible home with Today, kept on the device, and an invitation" do
    page.driver.browser.execute_cdp("Network.setUserAgentOverride", userAgent: APP_UA)
    phone
    visit root_path
    assert_selector ".hm-root.is-guest .hm-today"
    assert_no_selector ".ui-tabbar", visible: true
    click_on "Begin today"
    5.times { find(".tf-next").click }
    assert_text "Marks today done on this device"
    click_on "Amen"
    assert_selector ".tf-amen-streak", text: "Day one"
    assert_selector ".tf-keep", text: /Create a free account to keep your streak/
    assert_not DailyCompletion.where(date: DailyWord.today_date).exists?

    visit root_path
    assert_selector ".hm-today.is-done"
    assert_selector ".hm-done-keep", text: /keep your streak/
  end

  test "Amen with no signal waits in the outbox and reaches the server once back online" do
    sign_in
    visit today_begin_path
    wait_for_service_worker
    5.times { find(".tf-next").click }
    go_offline
    click_on "Amen"
    assert_selector ".tf-amen-title", text: "Today is done"
    sleep 0.5
    assert_not DailyCompletion.done_on?(users(:one))

    go_online
    page.execute_script("window.dispatchEvent(new Event('online'))")
    visit root_path # every page load flushes the outbox too
    Timeout.timeout(10) { sleep 0.2 until DailyCompletion.done_on?(users(:one)) }
    assert_selector ".hm-today.is-done"
  end

  private

  def phone
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 2, mobile: true)
  end

  def sign_in
    visit new_session_path
    fill_in "email_address", with: users(:one).email_address
    fill_in "password", with: "password"
    click_on "Sign In"
    assert_selector ".hm-today"
  end
end
