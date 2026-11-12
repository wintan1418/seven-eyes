require "application_system_test_case"

# The preach queue, rebuilt to beat EasyWorship's schedule. A tester ran it
# side by side with EasyWorship: there, a reference typed into the scripture
# search lists the chapter, a click previews, "Go Live" projects, and every
# verse used piles up in the schedule — all instant, all local. Here, adds
# waited on the server (later ones never showed), failed silently offline, the
# drawer covered the operator view and anything typed went straight to the
# projector. Now the queue is local-first, docked, and has Preview → Live.
class PreachQueueTest < ApplicationSystemTestCase
  include OfflineTestHelper

  SHOTS = ENV["QUEUE_SCREENSHOTS"].presence

  setup do
    clear_offline_data
    @user = users(:one)
    @user.update!(tour_completed_at: Time.current)
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    books = {
      "Ps" => [ "Psalms", 19, 150, { 23 => 1..4 } ],
      "Jer" => [ "Jeremiah", 24, 52, { 10 => 8..12 } ],
      "Matt" => [ "Matthew", 40, 28, { 10 => 8..11 } ],
      "John" => [ "John", 43, 21, { 11 => 30..40 } ],
      "Rom" => [ "Romans", 45, 16, { 8 => 26..30 } ],
      "Rev" => [ "Revelation", 66, 22, { 12 => 8..12 } ]
    }
    books.each do |osis, (name, position, chapters, verses)|
      book = Book.create!(osis_code: osis, name:, testament: position > 39 ? :new : :old, position:, chapter_count: chapters)
      verses.each do |chapter, range|
        range.each do |v|
          Verse.create!(translation: @kjv, book:, chapter:, verse_number: v, text: "KJV #{name} #{chapter}:#{v}")
        end
      end
    end
    @study = @user.studies.create!(name: "Sunday", pane_count: 1)
    @study.panes.first.update!(reference: "John 11", translation: @kjv)
  end

  teardown do
    go_online
    clear_offline_data
  end

  test "online: five references added in a row all show at once and are still there after a reload" do
    start_preaching

    # Docked beside the live view on a wide screen, not covering it.
    assert_selector ".ps-root.is-queue-open .ps-setlist-host.is-open"
    assert_no_selector ".ps-setlist-host.is-open .ps-book-backdrop", visible: true
    assert_operator find(".ps-setlist-panel").evaluate_script("this.getBoundingClientRect().left"), :>, 900

    refs = [ "Jn 11:35", "Rev 12:10", "Jer 10:11", "Jer 10:10", "Matt 10:10" ]
    timings = refs.map { |ref| time_to_visible(ref) }
    labels = [ "John 11:35", "Revelation 12:10", "Jeremiah 10:11", "Jeremiah 10:10", "Matthew 10:10" ]
    assert_equal labels, queue_labels
    report "Enter in queue input → item visible (online)", timings

    wait_until { @study.setlist_items.count == 5 }
    assert_equal labels, @study.setlist_items.in_order.map(&:label)
    assert_no_selector ".ps-setlist-item .sync", visible: true, wait: 5
    shot "online-queue"

    visit study_path(@study)
    wait_for_reader_js
    assert_equal labels, queue_labels
  end

  test "Preview never touches the projector until Go live" do
    start_preaching
    projector = open_projector
    within_window(projector) { assert_selector ".ps-verse.is-preach-current", text: "KJV John 11:30" }

    # Go box: Shift+Enter previews.
    find("body").send_keys("g")
    find(".ps-preach-jump input").send_keys("rev 12:10", [ :shift, :enter ])
    within(".ps-console") do
      assert_selector ".ps-console-preview[data-state='ready'] .what", text: "Revelation 12:10"
      assert_selector ".ps-preview-text", text: "KJV Revelation 12:10"
      assert_selector ".ps-console-row.is-live .what", text: "John 11:30"
      # The chapter verse list, with full text.
      assert_selector ".ps-verse-list .vrow", count: 5
      assert_selector ".ps-verse-list .vrow.is-preview", text: "KJV Revelation 12:10"
    end
    shot "preview-staged"
    sleep 0.6
    within_window(projector) { assert_selector ".ps-verse.is-preach-current", text: "KJV John 11:30" }
    assert_selector ".ps-pane.is-presented .ps-verse.is-preach-current[data-osis='John'][data-verse-num='30']"

    # L goes live.
    find("body").send_keys("l")
    assert_selector ".ps-pane.is-presented .ps-verse.is-preach-current[data-osis='Rev'][data-verse-num='10']", wait: 2
    within_window(projector) { assert_selector ".ps-verse.is-preach-current", text: "KJV Revelation 12:10", wait: 3 }
    assert_selector ".ps-console-row.is-live .what", text: "Revelation 12:10"
    report "Preview → live (operator paint)", [ find(".ps-root")["data-preview-to-live-ms"].to_f ]
    # …and it joined the queue by itself (the setting is on by default).
    assert_includes queue_labels, "Revelation 12:10"

    # A verse in the chapter list: click previews, the live verse stays marked.
    find(".ps-verse-list .vrow[data-num='11'] .pick").click
    assert_selector ".ps-console-preview .what", text: "Revelation 12:11"
    assert_selector ".ps-verse-list .vrow.is-live[data-num='10']"
    assert_selector ".ps-verse-list .vrow.is-preview[data-num='11']"
    within_window(projector) { assert_selector ".ps-verse.is-preach-current", text: "KJV Revelation 12:10" }
    # Double-click goes live.
    find(".ps-verse-list .vrow[data-num='12'] .pick").double_click
    within_window(projector) { assert_selector ".ps-verse.is-preach-current", text: "KJV Revelation 12:12", wait: 3 }
    shot "verse-list-live"
    projector.close
  end

  test "on a narrow screen the queue is a drawer that doesn't dim the screen, and opens for a preview" do
    page.driver.browser.manage.window.resize_to(1060, 900)
    start_preaching
    assert_no_selector ".ps-setlist-host.is-open"
    find("body").send_keys("g")
    find(".ps-preach-jump input").send_keys("rev 12:10", [ :shift, :enter ])
    assert_selector ".ps-setlist-host.is-open .ps-console-preview .what", text: "Revelation 12:10"
    assert_equal "0", find(".ps-setlist-host .ps-book-backdrop", visible: :all).evaluate_script("getComputedStyle(this).opacity")
    shot "narrow-preview"
    find(".ps-golive-btn").click
    assert_selector ".ps-pane.is-presented .ps-verse.is-preach-current[data-osis='Rev'][data-verse-num='10']", wait: 2
    assert_no_selector ".ps-setlist-host.is-open" # out of the way once it's live
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1000)
  end

  # (b) No signal at all, and "data on but dead" (requests hang, navigator.onLine stays true).
  { offline: :go_offline, dead: :go_dead_network }.each do |mode, cut|
    test "#{mode} network: add 3 references, drag to reorder, preview, go live on the projector — and it syncs on reconnect" do
      start_preaching
      projector = open_projector
      send(cut)

      ms = time_to_visible("Jn 11:35, Rev 12:10; Jer 10:10-11")
      labels = [ "John 11:35", "Revelation 12:10", "Jeremiah 10:10-11" ]
      assert_equal labels, queue_labels
      report "Enter in queue input → 3 items visible (#{mode})", ms
      assert_selector ".ps-setlist-item .sync", text: "Will sync when online", count: 3, wait: 5
      shot "#{mode}-queue-pending"

      # Drag Jeremiah (by its grip) to the top.
      grips = all(".ps-setlist-item .grip")
      grips[2].drag_to(grips[0])
      reordered = [ "Jeremiah 10:10-11", "John 11:35", "Revelation 12:10" ]
      assert_equal reordered, queue_labels

      # Preview: the projector stays put.
      find(".ps-setlist-item .present", text: "John 11:35").click
      assert_selector ".ps-console-preview[data-state='ready'] .what", text: "John 11:35"
      assert_selector ".ps-setlist-item.is-preview", text: "John 11:35"
      sleep 0.4
      within_window(projector) { assert_selector ".ps-verse.is-preach-current", text: "KJV John 11:30" }

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      find(".ps-golive-btn").click
      assert_selector ".ps-pane.is-presented .ps-verse.is-preach-current[data-osis='John'][data-verse-num='35']", wait: 2
      report "Preview → live, click to operator screen (#{mode}, wall clock)", [ (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000 ]
      within_window(projector) { assert_selector ".ps-verse.is-preach-current", text: "KJV John 11:35", wait: 3 }
      assert_selector ".ps-setlist-item.is-live", text: "John 11:35"
      assert_equal 3, all(".ps-setlist-item").size, "going live with a queued verse must not add it twice"
      assert_equal 0, @study.setlist_items.count

      go_online
      wait_until(timeout: 45) { @study.setlist_items.in_order.map(&:label) == reordered }
      assert_no_selector ".ps-setlist-item .sync", visible: true, wait: 15
      projector.close
    end
  end

  test "a Sunday offline: a 10-item queue built, run by keyboard alone, edited mid-service, then synced" do
    start_preaching
    projector = open_projector
    go_offline

    # Build the service: eight scriptures in one go, a song, a thought.
    field = find(".ps-setlist-form .ref-field")
    field.send_keys("Ps 23:1, Jn 11:35, Rom 8:28; Jer 10:10-11, Matt 10:10, Rev 12:10, Jn 11:40, Rom 8:26", :enter)
    find(".ps-setlist-form .kinds label", text: /song/i).click
    find(".ps-setlist-form .body-field").set("Amazing grace, how sweet the sound\n\nTwas grace that taught my heart to fear")
    find(".ps-setlist-form .title-field").send_keys("Amazing Grace", :enter)
    find(".ps-setlist-form .kinds label", text: /thought/i).click
    find(".ps-setlist-form .title-field").send_keys("Welcome & notices", :enter)
    assert_equal 10, queue_labels.size
    assert_equal "Amazing Grace", queue_labels[8]
    shot "sunday-queue-offline"

    watch_projector(projector)

    # Keyboard only from here. Esc leaves the field, Q → queue; Enter previews; Enter again goes live.
    page.send_keys(:escape, "q")
    assert_selector ".ps-setlist-item.is-selected", text: "Psalms 23:1"
    page.send_keys(:enter)
    assert_selector ".ps-console-preview .what", text: "Psalms 23:1"
    assert_equal 0, projector_changes(projector)
    page.send_keys(:enter)
    within_window(projector) { assert_selector ".ps-verse.is-preach-current", text: "KJV Psalms 23:1", wait: 3 }

    # N previews what's next, L sends it live, → walks the verses.
    assert_selector ".ps-console-row.is-next .what", text: "John 11:35"
    page.send_keys("n")
    assert_selector ".ps-console-preview .what", text: "John 11:35"
    page.send_keys("l")
    within_window(projector) { assert_selector ".ps-verse.is-preach-current", text: "KJV John 11:35", wait: 3 }
    page.send_keys(:right)
    within_window(projector) { assert_selector ".ps-verse.is-preach-current", text: "KJV John 11:36", wait: 3 }

    # Mid-service edits — the projector must not move.
    changes = projector_changes(projector)
    page.send_keys("q", :down) # the next item: Romans 8:28
    assert_selector ".ps-setlist-item.is-selected", text: "Romans 8:28"
    page.send_keys("e")
    assert_equal "Rom 8:28", find(".ps-setlist-form .ref-field").value
    page.send_keys("Rom 8:27", :enter)
    assert_selector ".ps-setlist-item", text: "Romans 8:27"
    page.send_keys([ :alt, :down ]) # Romans 8:27 after Jeremiah
    assert_equal [ "Jeremiah 10:10-11", "Romans 8:27" ], queue_labels[2, 2]
    page.send_keys(:delete)
    assert_selector ".ps-queue-toast", text: "Removed Romans 8:27"
    assert_equal 9, queue_labels.size
    page.send_keys("u")
    assert_equal [ "Jeremiah 10:10-11", "Romans 8:27" ], queue_labels[2, 2]
    sleep 0.3
    assert_equal changes, projector_changes(projector), "the projector changed during queue edits"
    within_window(projector) { assert_selector ".ps-verse.is-preach-current", text: "KJV John 11:36" }

    # The song: pick it, preview, live.
    page.send_keys("q")
    9.times { page.send_keys(:down) }
    page.send_keys(:up) # back to the song (item 9 of 10)
    assert_selector ".ps-setlist-item.is-selected", text: "Amazing Grace"
    page.send_keys(:enter, :enter)
    within_window(projector) { assert_selector "[data-preach-slide]", text: "Amazing grace, how sweet the sound", wait: 3 }
    shot "sunday-keyboard"

    # Back online: the server ends up with exactly the device's queue.
    expected = queue_labels
    go_online
    wait_until(timeout: 45) { @study.setlist_items.in_order.map(&:label) == expected }
    assert_equal 10, @study.setlist_items.count
    projector.close
  end

  private

  # Count every change of what the projector shows (verse or slide).
  def watch_projector(projector)
    within_window(projector) do
      page.execute_script(<<~JS)
        window.__changes = 0
        const root = document.querySelector(".ps-root")
        new MutationObserver(() => { window.__changes++ }).observe(root, { subtree: true, childList: true, attributes: true, attributeFilter: ["class"] })
      JS
    end
  end

  def projector_changes(projector)
    within_window(projector) { page.evaluate_script("window.__changes") }
  end

  def sign_in
    visit new_session_path
    fill_in "email_address", with: @user.email_address
    fill_in "password", with: "password"
    click_on "Sign In"
    assert_no_current_path new_session_path
  end

  # Signed in, study open, preach mode on with the study's Bible downloaded.
  def start_preaching
    sign_in
    visit study_path(@study)
    wait_for_service_worker
    wait_for_reader_js
    find(".ui-appbar button[data-action~='presentation#start']").click
    assert_selector ".ps-root.is-preaching"
    assert_selector ".ps-preach-offline[data-state='ready']", wait: 20
  end

  def open_projector
    operator = current_window
    projector = open_new_window
    within_window(projector) do
      visit "#{study_path(@study)}?output=1&pane=0"
      assert_selector ".ps-root.is-output .ps-verse.is-preach-current"
    end
    switch_to_window(operator)
    projector
  end

  def queue_labels
    all(".ps-setlist-item .lbl", visible: :all).map { |l| l.text(:all) }
  end

  # Type a reference and press Enter; ms until the new row is in the DOM and painted.
  def time_to_visible(ref)
    page.evaluate_async_script(<<~JS, ref)
      const [ref, done] = arguments
      const input = document.querySelector(".ps-setlist-form .ref-field")
      const before = document.querySelectorAll(".ps-setlist-item").length
      input.focus()
      input.value = ref
      const t0 = performance.now()
      input.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }))
      input.form.requestSubmit()
      const inDom = document.querySelectorAll(".ps-setlist-item").length > before ? performance.now() - t0 : null
      requestAnimationFrame(() => done(inDom == null ? -1 : performance.now() - t0))
    JS
  end

  def wait_until(timeout: 30)
    Timeout.timeout(timeout) { sleep 0.2 until yield }
  end

  def report(what, ms)
    ms = Array(ms).map(&:to_f)
    line = "#{what}: #{ms.map { |m| m.round(1) }.join(", ")} ms (max #{ms.max.round(1)})"
    puts "\n  ⏱ #{line}"
    File.open(File.join(SHOTS, "timings.txt"), "a") { |f| f.puts(line) } if SHOTS
  end

  def shot(name)
    page.save_screenshot(File.join(SHOTS, "#{name}.png")) if SHOTS
  end
end
