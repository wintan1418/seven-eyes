require "application_system_test_case"

# Start projecting with no internet. A tester arrived offline without a study
# opened beforehand and got "New studies need internet — you're offline": he
# couldn't project at all. Now, whenever a signed-in reader is online, the
# device quietly keeps their Quick Present study, its Bible and their recent
# studies ready, so "Present offline" (or "New study") works from the first tap.
class OfflineStartPresentTest < ApplicationSystemTestCase
  include OfflineTestHelper

  SHOTS = Rails.root.join("tmp/screenshots")

  setup do
    clear_offline_data
    FileUtils.mkdir_p(SHOTS)
    @user = users(:one)
    @user.update!(tour_completed_at: Time.current, guide_dismissed_at: Time.current)
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    (1..36).each do |verse|
      text = verse == 16 ? "For God so loved the world, that he gave his only begotten Son" : "KJV John 3:#{verse}"
      Verse.create!(translation: @kjv, book: john, chapter: 3, verse_number: verse, text:)
    end
    (1..3).each { |verse| Verse.create!(translation: @kjv, book: john, chapter: 1, verse_number: verse, text: "KJV John 1:#{verse}") }

    @recent = @user.studies.create!(name: "Sunday", pane_count: 1, last_opened_at: 1.hour.ago)
    @recent.panes.first.update!(reference: "John 1", translation: @kjv)
    # Older than the five most recent: not kept offline.
    5.times { |i| @user.studies.create!(name: "Older #{i}", last_opened_at: (i + 2).days.ago) }
    @oldest = @user.studies.create!(name: "Long ago", last_opened_at: 30.days.ago)
  end

  teardown do
    go_online
    clear_offline_data
  end

  test "offline, Present offline on the home page opens Quick Present and John 3:16 goes on the projector" do
    sign_in
    prepare_device

    go_offline
    visit root_path # the home page itself comes from the device
    assert_selector ".ps-offline-badge", text: /offline/i
    assert_selector ".hm-actions", text: /Quick Present is ready offline/i
    within(".hm-study-grid") do
      assert_selector ".hm-study.is-offline-ready", text: /Sunday.*Available offline/m
      assert_selector ".hm-study.is-offline-missing", text: /Long ago.*Needs internet to open/m
      find(".hm-study", text: "Long ago").click
    end
    assert_selector ".ui-offline-toast", text: /needs internet to open/i
    assert_current_path root_path
    page.save_screenshot(SHOTS.join("offline_home_studies.png").to_s)
    page.execute_script("document.querySelector('.hm-head').scrollIntoView({ block: 'start' })")
    page.save_screenshot(SHOTS.join("offline_home_present_offline.png").to_s)

    timings = present_john_316 { find(".hm-present").click }
    page.save_screenshot(SHOTS.join("offline_quick_present_projecting.png").to_s)
    report("offline", timings)
    assert timings[:enter_to_operator] < 2, "John 3:16 took #{timings[:enter_to_operator].round(2)} s on the operator"
    assert timings[:enter_to_projector] < 2, "John 3:16 took #{timings[:enter_to_projector].round(2)} s on the projector"

    # Another chapter, read from the downloaded Bible; it reaches the study
    # (outbox) once back online.
    find("body").send_keys("g")
    started = now
    find(".ps-preach-jump input").send_keys("jn 1 2", :enter)
    assert_selector ".ps-pane.is-presented .ps-verse.is-preach-current[data-chapter='1'][data-verse-num='2']", wait: 2
    report("offline, another chapter", { enter_to_operator: now - started })
    quick = @user.studies.find_by!(quick_present: true)
    assert_equal "John 3", quick.panes.first.reload.reference
    go_online
    # Chrome's emulated network change doesn't reach this tab's `online`
    # listeners once a popup (the projector) has been opened from it; a real
    # reconnection does. Fire it as the browser would.
    page.execute_script("window.dispatchEvent(new Event('online'))")
    Timeout.timeout(15) { sleep 0.2 until quick.panes.first.reload.reference.to_s.start_with?("John 1") }
  end

  test "New study with no internet opens Quick Present instead of a dead end" do
    sign_in
    prepare_device
    go_offline
    visit root_path
    find(".hm-section-head button", text: "New study").click
    assert_selector ".ps-root.is-preaching", wait: 5
    assert_selector ".ps-preach-jump input:focus"
    assert_no_selector ".ui-offline-toast.is-on", text: /new studies need/i
    assert_equal "Quick Present", Study.find(current_path[%r{\d+}]).name
  end

  test "data on but dead: Present offline still projects at once" do
    sign_in
    prepare_device

    go_dead_network # navigator.onLine stays true; every request hangs
    timings = present_john_316 { find(".hm-present").click }
    report("data on but dead", timings)
    assert timings[:tap_to_ready] < 3, "Quick Present took #{timings[:tap_to_ready].round(2)} s to open"
    assert timings[:enter_to_projector] < 2, "John 3:16 took #{timings[:enter_to_projector].round(2)} s on the projector"
  end

  test "Bible search works offline in a downloaded Bible and loads the passage on the device" do
    sign_in
    prepare_device

    go_offline
    visit study_path(@recent) # a recent study, opened from the device
    assert_selector ".ps-offline-badge", text: /reading from your downloads/i
    wait_for_reader_js
    find(".ui-appbar [data-action~='search#open']").click
    within(".ps-search-panel") do
      find("input[name='q']").send_keys("begotten son", :enter)
      assert_selector ".sr-summary", text: /Offline search · showing 1 verse containing begotten and son · KJV/i
      assert_selector ".sr-hit .sr-ref", text: "John 3:16"
      assert_text "For God so loved the world"
    end
    sleep 0.5 # the drawer's slide-in, for the picture
    page.save_screenshot(SHOTS.join("offline_bible_search.png").to_s)
    # A result opens its whole chapter on the device, the verse marked; the sheet closes.
    within(".ps-search-panel") { find(".sr-hit .sr-open", text: "John 3:16").click }
    assert_no_selector ".ps-search-drawer.is-open"
    assert_selector ".ps-pane .ps-verse.is-focus[data-chapter='3'][data-verse-num='16']", wait: 3
  end

  private

  def sign_in
    visit new_session_path
    fill_in "email_address", with: @user.email_address
    fill_in "password", with: "password"
    click_on "Sign In"
    assert_current_path root_path
  end

  # Online on the home page: Quick Present, its Bible and the recent studies
  # get ready by themselves.
  def prepare_device
    wait_for_service_worker
    assert_selector ".hm-actions", text: /Quick Present is ready offline/i, wait: 40
    assert_selector ".hm-study.is-offline-ready", text: "Sunday", wait: 40
    wait_for_warm_up # the app's own pages, saved in the background too
    page.save_screenshot(SHOTS.join("online_home_studies_available_offline.png").to_s)
  end

  # Tap (the block) → preach mode with the Go box → Project → "john 3 16" ↵.
  def present_john_316
    prefer_focus_view # these timings are for the full-screen slide (Focus view)
    t0 = now
    yield
    assert_selector ".ps-root.is-preaching .ps-preach-jump input:focus", wait: 5
    tap_to_ready = now - t0
    assert_equal "Quick Present", Study.find(current_path[%r{\d+}]).name

    operator = current_window
    projector = window_opened_by do
      find(".ps-preach-jump input").send_keys(:escape) # close the Go box to reach the preach bar
      find(".ps-preach-bar [data-preach-project]").click
    end
    within_window(projector) { assert_selector ".ps-root.is-output .ps-verse", wait: 5 }
    projector_open = now - t0
    switch_to_window(operator)

    find("body").send_keys("g")
    input = find(".ps-preach-jump input")
    input.send_keys("john 3 16")
    assert_selector ".ps-preach-jump-hint", text: "John 3:16", wait: 1
    t1 = now
    input.send_keys(:enter)
    assert_selector ".ps-pane.is-presented .ps-verse.is-preach-current[data-chapter='3'][data-verse-num='16']", wait: 2
    enter_to_operator = now - t1
    within_window(projector) do
      assert_selector ".ps-verse.is-preach-current", text: "For God so loved the world", wait: 3
    end
    enter_to_projector = now - t1
    within_window(projector) { page.save_screenshot(SHOTS.join("offline_projector_john_3_16.png").to_s) }
    total = now - t0
    { tap_to_ready:, projector_open:, enter_to_operator:, enter_to_projector:, total: }
  ensure
    projector&.close rescue nil # rubocop:disable Style/RescueModifier
    switch_to_window(operator) if operator
  end

  def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  def report(label, timings)
    line = timings.map { |k, v| "#{k}=#{(v * 1000).round} ms" }.join(" · ")
    puts "\n[offline start present · #{label}] #{line}"
    File.open(SHOTS.join("timings.txt"), "a") { |f| f.puts("#{label}: #{line}") }
  end
end
