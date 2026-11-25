require "application_system_test_case"

# "The offline projection is slow" — a church operator on a Windows laptop went
# back to EasyWorship mid-service. Her recording: with Wi-Fi off, each Go live
# took half a second or more between the button and the slide changing. Every
# Go live re-rendered the whole chapter from IndexedDB — the manifest, the
# download list, the book, then one read per verse for highlights (21 round
# trips for Revelation 19, 176 for Psalm 119), queued behind the queue's own
# writes — even when the verse was in the chapter already on the screen.
#
# These tests make every IndexedDB read take 15 ms (a slow disk) and time,
# inside the page, the key press → the slide on the operator's Live and on the
# projector window: the same chapter moves the highlight at once, a new
# chapter renders from the copy kept in memory.
class OfflineProjectionSpeedTest < ApplicationSystemTestCase
  include OfflineTestHelper

  IDB_READ_MS = 15
  QUICK_MS = 250 # was ~500 with a 15 ms disk

  # Each readonly IndexedDB answer arrives IDB_READ_MS late.
  SLOW_DISK_JS = <<~'JS'.freeze
    (() => {
      const delay = __DELAY__
      const desc = Object.getOwnPropertyDescriptor(IDBRequest.prototype, "onsuccess")
      Object.defineProperty(IDBRequest.prototype, "onsuccess", {
        configurable: true,
        get() { return desc.get.call(this) },
        set(fn) {
          let readonly = false
          try { readonly = !!this.transaction && this.transaction.mode === "readonly" } catch (e) {}
          const req = this
          desc.set.call(this, readonly && typeof fn === "function" ? function (e) { setTimeout(() => fn.call(req, e), delay) } : fn)
        }
      })
    })()
  JS

  # Stamps the last key press / mouse press, and the moment a condition first holds.
  STOPWATCH_JS = <<~'JS'.freeze
    if (!window.__sw) {
      const sw = window.__sw = { start: 0, hit: 0, cond: null }
      const mark = (e) => { if (sw.kinds.includes(e.type)) sw.start = Date.now() }
      ;[ "keydown", "mousedown", "dblclick" ].forEach((t) => window.addEventListener(t, mark, true))
      const check = () => { if (sw.cond && !sw.hit) { try { if (sw.cond()) sw.hit = Date.now() } catch (e) {} } }
      new MutationObserver(check).observe(document.documentElement, { subtree: true, childList: true, attributes: true, characterData: true })
      setInterval(check, 4)
    }
  JS

  # In the projector window: report every change of the verse on screen.
  PROJECTOR_REPORTS_JS = <<~'JS'.freeze
    (() => {
      const ch = new BroadcastChannel("ps-test-projector")
      let last = null
      const check = () => {
        const now = [ ...document.querySelectorAll(".ps-verse.is-preach-current") ].map((v) => `${v.dataset.chapter}:${v.dataset.verseNum}`).join(",")
        if (now !== last) { last = now; ch.postMessage({ shown: now, at: Date.now() }) }
      }
      new MutationObserver(check).observe(document.documentElement, { subtree: true, childList: true, attributes: true })
      setInterval(check, 4)
    })()
  JS

  setup do
    clear_offline_data
    @user = users(:one)
    @user.update!(tour_completed_at: Time.current)
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    rev = Book.create!(osis_code: "Rev", name: "Revelation", testament: :new, position: 66, chapter_count: 22)
    rows = (18..20).flat_map do |chapter|
      (1..26).map do |verse|
        { translation_id: @kjv.id, book_id: rev.id, chapter:, verse_number: verse,
          text: "Revelation #{chapter}:#{verse} — and I fell at his feet to worship him." }
      end
    end
    Verse.insert_all(rows)
    @study = @user.studies.create!(name: "Service · 29 Nov 2026", pane_count: 1)
    @study.panes.first.update!(reference: "Rev 18:1", translation: @kjv)
  end

  teardown do
    go_online
    clear_offline_data
  end

  test "with no signal and a slow disk, Go live changes the screen at once" do
    sign_in
    open_console
    projector = open_projector
    slow_disk
    go_offline

    # Abbey's flow: a reference, Enter (Preview), L (live).
    type_reference "rev 19:10"
    assert_selector ".cx-findhint", text: "Revelation 19:10" # read on the device
    find(".cx-find-input").send_keys(:enter) # Preview; the box lets go, so L is Go live
    assert_selector ".ps-console-preview .what", text: "Revelation 19:10"
    timed("L, a new chapter", live(19, 10), projector:) { press "l" }

    # The next reference in the same chapter: no re-render at all.
    type_reference "rev 19:11"
    assert_selector ".cx-findhint", text: "Revelation 19:11"
    find(".cx-find-input").send_keys(:enter)
    assert_selector ".ps-console-preview .what", text: "Revelation 19:11"
    timed("L, same chapter", live(19, 11), projector:) { press "l" }

    # Double-click a verse in the chapter list: straight to the screen.
    row = find(".ps-verse-list .vrow[data-num='9'] .pick")
    timed("double-click a verse", live(19, 9), projector:, on: %w[dblclick]) { row.double_click }

    # Shift+Enter into another chapter, and back: rendered from memory.
    type_reference "rev 20:4"
    timed("Shift+Enter, another chapter", live(20, 4), projector:) { find(".cx-find-input").send_keys([ :shift, :enter ]) }
    type_reference "rev 19:2"
    timed("Shift+Enter, back again", live(19, 2), projector:) { find(".cx-find-input").send_keys([ :shift, :enter ]) }

    timed("Next", live(19, 3), projector:) { find(".ps-preach-bar-right [data-action~='presentation#next']").click }

    # What went live is in the queue, waiting for a signal.
    assert_selector ".ps-setlist-item", text: "Revelation 19:10"
    assert_selector ".ps-setlist-item", text: /sync when online/i

    go_online
    projector.close
  end

  test "L right after a reference puts it on the screen; L inside words still types" do
    sign_in
    open_console
    go_offline

    type_reference "rev 19:5"
    find(".cx-find-input").send_keys("l")
    assert_selector live_selector(19, 5), wait: 2
    assert_equal "rev 19:5", find(".cx-find-input").value # the L wasn't typed

    # A verse number alone ("12" = verse 12 of the chapter on screen) + L.
    type_reference "12"
    find(".cx-find-input").send_keys("L")
    assert_selector live_selector(19, 12), wait: 2

    # Letters that are part of what is typed still type.
    type_reference "revelation 19"
    find(".cx-find-input").send_keys(" l")
    assert_equal "revelation 19 l", find(".cx-find-input").value
    find(".cx-mode-btn[data-mode='words']").click
    type_reference "fell at his feet 1"
    find(".cx-find-input").send_keys("l")
    assert_equal "fell at his feet 1l", find(".cx-find-input").value
    assert_selector live_selector(19, 12) # unchanged

    go_online
  end

  test "a service projected with no signal is on Past services until it syncs" do
    sign_in
    visit services_path
    assert_selector ".sv-empty"
    wait_for_service_worker
    go_offline

    # What the queue leaves in the outbox when something goes live offline
    # (lib/offline/served.js → queueServed).
    page.evaluate_async_script(<<~JS, @study.id.to_s, owner_key, Time.current.iso8601)
      const [ studyId, owner, at, done ] = arguments
      const q = indexedDB.open("bibliorata-offline")
      q.onsuccess = () => {
        const tx = q.result.transaction("outbox", "readwrite")
        tx.objectStore("outbox").add({
          kind: "service-served", key: `served:${studyId}:${at.slice(0, 10)}`, owner,
          url: `/studies/${studyId}/service/served`, method: "POST", format: "json", body: { at },
          studyId, name: "Service · 29 Nov 2026", rev: 0, createdAt: Date.now(), updatedAt: Date.now()
        })
        tx.oncomplete = () => { new BroadcastChannel("ps-offline").postMessage({ type: "outbox", pending: 0 }); done(true) }
        tx.onerror = () => done(false)
      }
      q.onerror = () => done(false)
    JS
    within(".sv-list") do
      assert_selector ".sv-row.is-pending .sv-name", text: /Service · 29 Nov 2026/
      assert_selector ".sv-row.is-pending .sv-tag", text: "Today"
      assert_text "waiting to sync"
    end
    assert_no_selector ".sv-empty", visible: true

    # Signal back: the ping syncs, and the server lists it.
    go_online
    page.execute_script("window.dispatchEvent(new Event('online'))")
    Timeout.timeout(15) { sleep 0.1 until @study.reload.last_served_at }
    visit services_path
    assert_selector ".sv-row:not(.is-pending)[data-study-id='#{@study.id}'] .sv-tag", text: "Today"
    assert_no_selector ".sv-row.is-pending"
  end

  private

  def sign_in
    visit new_session_path
    fill_in "email_address", with: @user.email_address
    fill_in "password", with: "password"
    click_on "Sign In"
    assert_no_current_path new_session_path
  end

  def owner_key = page.evaluate_script("document.body.dataset.offlineOwner")

  # From now on, in the operator's page.
  def slow_disk
    page.execute_script(SLOW_DISK_JS.sub("__DELAY__", IDB_READ_MS.to_s))
  end

  def open_console
    visit study_path(@study)
    wait_for_service_worker
    wait_for_reader_js
    mark_console_tour_seen
    find(".ui-appbar button[data-action~='presentation#start']").click
    assert_selector ".ps-root.is-console"
    assert_selector ".ps-preach-offline[data-state='ready']", wait: 30
  end

  # The projector window, opened while the network was fine. It reports what
  # it shows to the operator's page, so timing it needs no window switching
  # (which can leave key presses going nowhere in headless Chrome).
  def open_projector
    operator = current_window
    projector = open_new_window
    within_window(projector) do
      visit "#{study_path(@study)}?output=1&pane=0"
      assert_selector ".ps-root.is-output .ps-verse.is-preach-current"
      page.execute_script(PROJECTOR_REPORTS_JS)
    end
    switch_to_window(operator)
    page.execute_script(<<~JS)
      window.__projector = []
      new BroadcastChannel("ps-test-projector").onmessage = (e) => window.__projector.push(e.data)
    JS
    projector
  end

  # The library's box connects lazily: type again if a late connect wiped it.
  # A key press to whatever has focus (a WebDriver send_keys on <body> can go
  # astray once a second window has been opened).
  def press(key)
    page.driver.browser.action.send_keys(key).perform
  end

  def type_reference(text)
    3.times do
      input = find(".cx-find-input")
      input.fill_in(with: "")
      input.send_keys(text)
      break if has_field?(class: "cx-find-input", with: text, wait: 0.3) && find(".cx-findhint").text.present?
    end
  end

  def live_selector(chapter, verse)
    ".ps-pane.is-presented .ps-verse.is-preach-current[data-osis='Rev'][data-chapter='#{chapter}'][data-verse-num='#{verse}']"
  end

  def live(chapter, verse) = [ chapter, verse ]

  def arm_stopwatch(selector, kinds)
    page.execute_script(STOPWATCH_JS)
    page.execute_script("Object.assign(window.__sw, { hit: 0, start: 0, kinds: #{kinds.to_json} }); " \
                        "window.__sw.cond = () => !!document.querySelector(#{selector.to_json})")
  end

  # Runs the block (one key press / click) and asserts the operator's Live and
  # the projector show chapter:verse within QUICK_MS of it.
  def timed(what, (chapter, verse), projector: nil, on: %w[keydown mousedown])
    arm_stopwatch(live_selector(chapter, verse), on)
    yield
    operator_ms = stopwatch
    assert operator_ms, "#{what}: Revelation #{chapter}:#{verse} never went live"
    assert operator_ms < QUICK_MS, "#{what}: #{operator_ms} ms to the operator's Live"
    return unless projector

    projector_ms = Timeout.timeout(5) do
      loop do
        ms = page.evaluate_script(<<~JS)
          (() => {
            const hit = window.__projector.find((r) => r.at >= window.__sw.start && r.shown.split(",")[0] === "#{chapter}:#{verse}")
            return hit ? hit.at - window.__sw.start : null
          })()
        JS
        break ms if ms
        sleep 0.02
      end
    end
    assert projector_ms < QUICK_MS, "#{what}: #{projector_ms} ms to the projector"
  end

  def stopwatch(timeout: 5)
    Timeout.timeout(timeout) do
      loop do
        start, hit = page.evaluate_script("[window.__sw.start, window.__sw.hit]")
        return hit - start if hit.to_i > 0 && start.to_i > 0
        sleep 0.02
      end
    end
  rescue Timeout::Error
    nil
  end
end
