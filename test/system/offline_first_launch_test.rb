require "application_system_test_case"

# One visit with internet is enough, like a native Bible app: the service
# worker saves the app's start pages as soon as it takes control (even the
# page that registered it), the KJV downloads by itself, and with no signal
# every tab opens something usable — never the "you're offline" dead end.
class OfflineFirstLaunchTest < ApplicationSystemTestCase
  include OfflineTestHelper

  setup do
    clear_offline_data
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    (2..5).each do |chapter|
      (1..3).each { |v| Verse.create!(translation: @kjv, book: john, chapter:, verse_number: v, text: "KJV John #{chapter}:#{v}") }
    end
  end

  teardown do
    go_online
    clear_offline_data
  end

  test "a guest's first visit to /read is enough: the Bible, home and plans open offline, chapters turn" do
    visit read_path # the first page ever: no worker controls it yet
    study_path = current_path
    assert_match %r{\A/studies/\d+\z}, study_path
    assert_selector ".ps-verse-text", text: "KJV John 3:1"
    wait_for_service_worker
    wait_for_saved_page(study_path) # saved although the worker didn't control its load
    wait_for_saved_page(root_path)
    wait_for_saved_page(more_path)
    wait_for_saved_page(search_path)
    wait_for_bible("KJV") # downloaded by itself — nobody pressed Download

    go_offline
    visit read_path
    assert_current_path study_path
    assert_selector ".ps-verse-text", text: "KJV John 3:1"
    find(".rd-chapter-nav .rd-fab.next").click
    assert_selector ".ps-verse-text", text: "KJV John 4:1"
    find(".rd-chapter-nav .rd-fab.next").click
    assert_selector ".ps-verse-text", text: "KJV John 5:1"

    visit root_path
    assert_current_path root_path
    assert_no_text "You appear to be offline"
    assert_no_text "needs one visit"

    visit more_path
    assert_no_text "You appear to be offline"

    # The Search tab, and a result's /read?ref=… link, with no signal.
    visit search_path
    assert_selector ".sr-page .sr-input"
    visit read_path(ref: "John 4:2", t: "KJV")
    assert_current_path study_path
    assert_selector ".ps-verse-text", text: "KJV John 4:2"

    # Guests have no plans to save: a calm page that links to what works.
    visit reading_plans_path
    assert_text "Reading plans needs one visit with internet"
    assert_link "Bible", href: "/read"

    # A study never opened on this device: the offline reader, from the KJV.
    visit "/studies/#{Study.maximum(:id) + 100}"
    assert_text "That study isn’t saved on this device yet"
    assert_selector ".ofr-verse-text", text: "KJV John 3:1"
    click_on "Next ›"
    assert_selector ".ofr-title", text: "John 4"
    assert_selector ".ofr-verse-text", text: "KJV John 4:2"
    click_on "John 4 ▾"
    find("summary", text: "John").click
    click_on "2"
    assert_selector ".ofr-verse-text", text: "KJV John 2:3"
  end

  test "with nothing saved for the study, /read still opens a Bible offline" do
    visit read_path
    wait_for_service_worker
    wait_for_bible("KJV")
    wait_for_saved_page(root_path)
    page.evaluate_async_script(<<~JS)
      const done = arguments[0]
      caches.open("ps-pages").then(async (c) => {
        for (const r of await c.keys()) if (/\\/studies\\//.test(r.url)) await c.delete(r)
      }).then(() => done(), () => done())
    JS

    go_offline
    visit read_path
    assert_selector ".ofr-title", text: "John 3"
    assert_selector ".ofr-verse-text", text: "KJV John 3:1"
  end

  test "a signed-in reader's plans, each plan and today's reading open offline without visiting them first" do
    user = users(:one)
    user.update!(tour_completed_at: Time.current, guide_dismissed_at: Time.current)
    study = user.studies.create!(name: "Plan: Gospel", pane_count: 1, last_opened_at: 1.day.ago)
    study.panes.first.update!(reference: "John 3", translation: @kjv)
    plan = user.reading_plans.create!(name: "Gospel", start_date: Date.current, study:)
    today = plan.plan_days.create!(day_number: 1, refs: "John 4")
    plan.plan_days.create!(day_number: 2, refs: "John 5")

    visit new_session_path
    fill_in "email_address", with: user.email_address
    fill_in "password", with: "password"
    click_on "Sign In"
    assert_no_current_path new_session_path
    wait_for_service_worker
    wait_for_saved_page(reading_plans_path, timeout: 30)
    wait_for_saved_page(reading_plan_path(plan), timeout: 30)
    wait_for_saved_page(study_path(study), timeout: 30)
    wait_for_bible("KJV")

    go_offline
    visit reading_plans_path
    assert_link href: reading_plan_path(plan) # the list itself, from the device
    visit reading_plan_path(plan) # never opened on this device, saved by the warm-up
    assert_selector ".ps-offline-badge", text: /offline/i # the page's scripts are running
    within("##{ActionView::RecordIdentifier.dom_id(today)}") { click_on "Mark done" }
    assert_selector ".ps-sync-pill", text: "1 change waiting to sync"
    click_on "Begin today's reading"
    assert_selector ".ps-verse-text", text: "KJV John 4:1"

    go_online
    assert_selector ".ps-sync-pill", text: "All changes saved", wait: 10
    assert today.reload.completed?
  end

  private

  # Like OfflineTestHelper#wait_for_saved_page, with room for the whole warm-up.
  def wait_for_saved_page(path, timeout: 20)
    Timeout.timeout(timeout) do
      sleep 0.2 until page.evaluate_async_script(<<~JS, path)
        const [path, done] = arguments
        caches.open("ps-pages").then(c => c.match(new URL(path, location.origin).href)).then(r => done(!!r), () => done(false))
      JS
    end
  rescue Timeout::Error
    flunk "#{path} was never saved for offline use"
  end

  def wait_for_bible(code, timeout: 30)
    Timeout.timeout(timeout) do
      sleep 0.2 until page.evaluate_async_script(<<~JS, code)
        const [code, done] = arguments
        const q = indexedDB.open("bibliorata-offline")
        q.onupgradeneeded = () => q.transaction.abort() // not made yet: leave it to the app
        q.onsuccess = () => {
          try {
            const r = q.result.transaction("bibles").objectStore("bibles").get(code)
            r.onsuccess = () => done(!!r.result); r.onerror = () => done(false)
          } catch (e) { done(false) }
        }
        q.onerror = () => done(false)
      JS
    end
  rescue Timeout::Error
    flunk "the #{code} Bible never downloaded by itself"
  end
end
