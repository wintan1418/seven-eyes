require "application_system_test_case"

# Phase 2B — the tools a church tester missed from EasyWorship, built to beat
# it on a laptop that is often offline: two scriptures in two Bibles on ONE
# slide, a PDF presentation stepped page by page, seminar slides with a
# presenter view, song collections, reusable service templates and an order of
# service for the WhatsApp group.
class SlideToolsTest < ApplicationSystemTestCase
  include OfflineTestHelper

  SHOTS = ENV["SLIDE_SCREENSHOTS"].presence

  COL_2_2 = "That their hearts might be comforted, being knit together in love"
  MATT_28_19 = "Therefore go and make disciples of all nations"

  setup do
    clear_offline_data
    @user = users(:one)
    @user.update!(tour_completed_at: Time.current)
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @bsb = Translation.create!(code: "BSB", name: "Berean Standard Bible")
    john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    col = Book.create!(osis_code: "Col", name: "Colossians", testament: :new, position: 51, chapter_count: 4)
    matt = Book.create!(osis_code: "Matt", name: "Matthew", testament: :new, position: 40, chapter_count: 28)
    (1..4).each { |v| Verse.create!(translation: @kjv, book: john, chapter: 3, verse_number: v, text: "KJV John 3:#{v}") }
    (1..3).each { |v| Verse.create!(translation: @kjv, book: col, chapter: 2, verse_number: v, text: v == 2 ? COL_2_2 : "KJV Colossians 2:#{v}") }
    (18..20).each { |v| Verse.create!(translation: @bsb, book: matt, chapter: 28, verse_number: v, text: v == 19 ? MATT_28_19 : "BSB Matthew 28:#{v}") }
    (18..20).each { |v| Verse.create!(translation: @kjv, book: matt, chapter: 28, verse_number: v, text: "KJV Matthew 28:#{v}") }
    @study = @user.studies.create!(name: "Sunday", pane_count: 1)
    @study.panes.first.update!(reference: "John 3", translation: @kjv)
  end

  teardown do
    go_online
    clear_offline_data
  end

  test "two references in two Bibles typed on one line become one projected slide, reference on top in gold" do
    start_preaching
    projector = open_projector

    open_tool "Scriptures"
    within(".ps-tool-dialog[aria-label='Scripture slide']") do
      find(".set-input").send_keys("Col 2:2; Matt 28:19 BSB")
      assert_selector ".set-hint[data-tone='ok']", text: "Colossians 2:2 KJV + Matthew 28:19 BSB"
      find(".set-input").send_keys(:enter)
      assert_selector ".ref-row.is-ready", count: 2, wait: 10
      assert_selector ".ref-row", text: COL_2_2
      assert_selector ".ref-row", text: MATT_28_19
      assert_equal %w[KJV BSB], all(".ref-row select.tr").map(&:value)
      # The little screen shows one slide with both passages, references above.
      assert_selector ".set-screen .set-block", count: 2
      assert_equal [ "COLOSSIANS 2:2 (KJV)", "MATTHEW 28:19 (BSB)" ], all(".set-screen .set-ref").map { |r| r.text.upcase }
      assert_selector ".set-pager .n", text: "Slide 1 of 1"
      click_on "Hide" # verse numbers off
      assert_no_selector ".set-screen .set-vnum"
      click_on "Show"
      assert_selector ".set-screen .set-vnum", count: 2
    end
    shot "composer"
    find(".ps-tool-dialog[aria-label='Scripture slide'] .set-input").send_keys([ :control, :enter ])
    assert_no_selector ".ps-tool-dialog[aria-label='Scripture slide']"

    queue_item("Colossians 2:2 KJV + Matthew 28:19 BSB").click
    within(".ps-console-preview") { assert_selector ".ps-preview-text .slide", count: 1, text: /Colossians 2:2 \(KJV\)/ }
    find(".ps-golive-btn").click
    within_window(projector) do
      assert_selector "[data-preach-slide] .slide-stanza.is-set .set-ref", count: 2, wait: 5
      assert_selector "[data-preach-slide] .set-block", text: COL_2_2
      assert_selector "[data-preach-slide] .set-block", text: MATT_28_19
      ref_color = find("[data-preach-slide] .set-ref", match: :first).evaluate_script("getComputedStyle(this).color")
      words_color = find("[data-preach-slide] .set-words", match: :first).evaluate_script("getComputedStyle(this).color")
      assert_equal "rgb(168, 111, 0)", ref_color # gold on the default (vellum) screen
      assert_not_equal words_color, ref_color
      shot "projected-two-verse-slide"
    end

    wait_until { @study.setlist_items.scripture_set.exists? }
    saved = @study.setlist_items.scripture_set.sole
    assert_equal [ [ "Colossians 2:2", "KJV" ], [ "Matthew 28:19", "BSB" ] ], saved.data["refs"].map { |r| [ r["label"], r["translation"] ] }
    assert_includes saved.body, MATT_28_19
    projector.close
  end

  test "a PDF imports on the device, steps page by page with thumbnails in Preview, and nothing is uploaded" do
    start_preaching
    projector = open_projector

    # Opening the tool once online keeps the PDF reader on the device…
    open_tool "Presentation"
    assert_text "Save it as a PDF first"
    wait_for_cached "/vendor/pdfjs-4.10.38/pdf.worker.min.js"
    find(".ps-tool-dialog[aria-label='Presentation'] .close").click
    # …so the import itself works with no signal (a flash drive in a village church).
    go_offline
    open_tool "Presentation"
    within(".ps-tool-dialog[aria-label='Presentation']") do
      find("input[type='file'][accept*='pdf']", visible: :all).attach_file(file_fixture("three_pages.pdf"))
      assert_selector ".pres-thumbs .thumb img[src^='blob:']", count: 3, wait: 20
      assert_selector ".pres-result .count", text: "3 pages"
      assert_equal "three pages", find("#pres-title").value
      fill_in "pres-title", with: "Building project"
      click_on "Add to queue"
    end
    assert_no_selector ".ps-tool-dialog[aria-label='Presentation']"

    assert_selector ".ps-setlist-item.kind-presentation .meta", text: /3 pages/i
    go_online
    queue_item("Building project").click
    within(".ps-console-preview") do
      assert_selector ".ps-preview-text.is-deck .slide.is-thumb img[src^='blob:']", count: 3, wait: 5
    end
    shot "pdf-presentation-preview"
    find(".ps-golive-btn").click
    within_window(projector) { assert_selector "[data-preach-slide] .slide-img.is-deck img[src^='blob:'][alt='Page 1']", wait: 5 }
    page.send_keys(:right)
    within_window(projector) { assert_selector "[data-preach-slide] .slide-img.is-deck img[alt='Page 2']", wait: 5 }
    assert_selector "[data-preach-counter] .num", text: /page 2/i
    assert_selector ".ps-preview-text .slide.is-live[data-index='1']"

    wait_until { @study.setlist_items.presentation.exists? }
    deck = @study.setlist_items.presentation.sole
    assert_equal 3, deck.data["pages"]
    assert_match(/\Adeck-/, deck.data["deck"])
    assert_nil deck.media_url # pages stay on the device
    projector.close
  end

  test "seminar slides: build them, reveal points one by one, and the stage shows notes and a timer" do
    start_preaching
    stage = open_stage

    open_tool "Seminar"
    within(".ps-tool-dialog[aria-label='Seminar slides']") do
      find(".deck-title").set("Leadership seminar")
      find(".sem-layouts button", text: "Title", exact_text: true).click
      fill_in "sem-title", with: "Servant Leadership"
      fill_in "sem-text", with: "Session one"
      fill_in "sem-notes", with: "Welcome everyone, pray first"
      all(".sem-row .pick")[1].click
      fill_in "sem-title", with: "Three marks of a leader"
      fill_in "sem-text", with: "Serves\nModels\nMultiplies"
      fill_in "sem-notes", with: "Story about Nehemiah"
      check "Reveal points one at a time"
      assert_selector ".set-screen .sem-points li", count: 3
      assert_selector ".sem-row", count: 2
    end
    shot "seminar-builder"
    within(".ps-tool-dialog[aria-label='Seminar slides']") { click_on "Add to queue" }

    queue_item("Leadership seminar").click
    find(".ps-golive-btn").click
    assert_selector "[data-preach-slide] .sem-title", text: "Servant Leadership"
    page.send_keys(:right)
    assert_selector "[data-preach-slide] .sem-points li:not(.is-hidden)", count: 1
    page.send_keys(:right)
    assert_selector "[data-preach-slide] .sem-points li:not(.is-hidden)", count: 2
    assert_selector "[data-preach-counter]", text: /point 2\/3/i
    within_window(stage) do
      assert_selector ".ps-stage.is-presenter .ps-stage-notes", text: "Story about Nehemiah", wait: 5
      assert_selector ".ps-stage [data-stage-timer]", text: /⏱ \d+:\d\d/
      assert_selector "[data-stage-next]", text: "Multiplies"
      shot "stage-presenter-view"
    end

    # Seminar mode: the verse-only tools leave the preach bar.
    open_tool "Seminar"
    within(".ps-tool-dialog[aria-label='Seminar slides']") do
      click_on "Seminar mode"
      assert_selector ".mode-toggle[aria-pressed='true']"
      find(".close").click
    end
    assert_selector ".ps-root.is-seminar"
    assert_no_selector ".ps-preach-bar [data-preach-parallel]"

    wait_until { @study.setlist_items.seminar.exists? }
    assert_equal [ "Servant Leadership", "Three marks of a leader" ], @study.setlist_items.seminar.sole.data["slides"].map { |s| s["title"] }
    stage.close
  end

  test "song collections: make one, add a hymn, filter by it — and it still opens offline" do
    start_preaching
    open_song_bank
    within(".ps-song-bank") do
      find(".coll-new input").send_keys("Communion", :enter)
      assert_selector ".coll.is-on .name", text: "Communion"
      assert_selector ".bank-empty", text: "Communion is empty"
      find(".coll .pick", text: "Communion").click # back to all songs
      find(".bank-search").send_keys("when i survey")
      assert_selector ".bank-row.is-picked .t", text: "When I Survey"
      find(".bank-preview .colls .chip", text: "Communion").click
      assert_selector ".bank-preview .colls .chip.is-on", text: "✓ Communion"
      assert_selector ".coll .n", text: "1"
      find(".coll-new input").send_keys("Christmas", :enter)
      find(".bank-search").set("")
      find(".coll .pick", text: "Communion").click
      assert_selector ".bank-row", count: 1
      assert_selector ".bank-row .t", text: "When I Survey"
    end
    shot "collections-sidebar"
    wait_until { @user.song_collections.find_by(name: "Communion")&.titles == [ "When I Survey the Wondrous Cross" ] }
    assert @user.song_collections.exists?(name: "Christmas")

    find(".ps-song-bank .close").click
    go_offline
    open_song_bank
    within(".ps-song-bank") do
      find(".coll .pick", text: "Communion").click
      assert_selector ".bank-row", count: 1, text: "When I Survey"
    end
  end

  test "save the service order as a template, add it to another queue offline, and start a new service from it" do
    start_preaching
    add_scripture "John 3:16"
    open_tool "Scriptures"
    within(".ps-tool-dialog[aria-label='Scripture slide']") do
      find(".set-input").send_keys("Col 2:2; Matt 28:19 BSB", :enter)
      assert_selector ".ref-row.is-ready", count: 2, wait: 10
      click_on "Add to queue"
    end
    assert_selector ".ps-setlist-item", count: 2

    open_tool "Templates"
    within(".ps-tool-dialog[aria-label='Service templates']") do
      find("#tpl-name").set("Sunday Service")
      click_on "Save template"
      assert_selector ".tpl-status", text: "Saved “Sunday Service” — 2 items"
      assert_selector ".tpl-row .t", text: "Sunday Service"
    end
    wait_until { @user.service_templates.exists?(name: "Sunday Service") }
    assert_equal %w[scripture scripture_set], @user.service_templates.sole.items.map { |i| i["kind"] }
    shot "service-template-picker"

    # Next week: a fresh study, no signal — the template is on the device.
    find(".ps-tool-dialog[aria-label='Service templates'] .close").click
    within(".ps-setlist-items") { all(".ps-setlist-item").size.times { first(".ps-setlist-item .danger", visible: :all).execute_script("this.click()") } }
    assert_no_selector ".ps-setlist-item"
    go_offline
    open_tool "Templates"
    within(".ps-tool-dialog[aria-label='Service templates']") { click_on "Add to this queue" }
    assert_selector ".ps-setlist-item", count: 2
    assert_selector ".ps-setlist-item.kind-scripture_set", text: "Colossians 2:2 KJV + Matthew 28:19 BSB"
    go_online

    open_tool "Templates"
    within(".ps-tool-dialog[aria-label='Service templates']") { click_on "New service" }
    wait_until { @user.studies.where("name LIKE ?", "Sunday Service — %").exists? }
    assert_no_selector ".ps-root.is-preaching", wait: 10 # a fresh page
    new_study = @user.studies.where("name LIKE ?", "Sunday Service — %").sole
    assert_current_path study_path(new_study)
    assert_equal %w[scripture scripture_set], new_study.setlist_items.in_order.map(&:kind)
  end

  test "the order of service copies as WhatsApp text" do
    start_preaching
    add_scripture "John 3:16"
    open_tool "Order"
    within(".ps-order-dialog") do
      fill_in "order-title", with: "Sunday Service"
      assert_selector ".order-sheet h2", text: "Sunday Service"
      assert_selector ".order-sheet .sheet-list li", text: "John 3:16"
      click_on "Copy for WhatsApp"
      assert_selector ".tpl-status", text: /copied|couldn't copy/i
      assert_match(/\A\*Sunday Service\*\n.+\n\n1\. 📖 John 3:16\z/, find(:xpath, ".").native.attribute("data-copied").to_s)
    end
    shot "order-of-service"
  end

  private

  def add_scripture(ref)
    find(".ps-setlist-panel").execute_script("this.scrollTop = this.scrollHeight")
    find(".ps-setlist-form .ref-field").send_keys(ref, :enter)
    assert_selector ".ps-setlist-item", text: ref
  end

  def open_song_bank
    find(".ps-setlist-panel").execute_script("this.scrollTop = this.scrollHeight")
    label = find(".ps-setlist-form .kinds label", text: /song/i)
    label.click unless label[:class].to_s.include?("is-on")
    find(".ps-song-library .lib-toggle").click
    assert_selector ".ps-song-bank .bank-row", minimum: 1, wait: 10
  end

  # The queue column scrolls under its sticky console: bring the row into the clear first.
  def queue_item(text)
    row = find(".ps-setlist-item", text: text)
    find(".ps-setlist-panel").execute_script("this.scrollTop = 0")
    row.execute_script("this.closest('.ps-setlist-items').scrollTop = this.offsetTop - 20")
    row.find(".present")
  end

  def open_tool(name)
    find(".ps-setlist-panel").execute_script("this.scrollTop = this.scrollHeight")
    find(".ps-queue-tools button", text: name).click
  end

  def sign_in
    visit new_session_path
    fill_in "email_address", with: @user.email_address
    fill_in "password", with: "password"
    click_on "Sign In"
    assert_no_current_path new_session_path
  end

  def start_preaching
    sign_in
    visit study_path(@study)
    wait_for_service_worker
    wait_for_reader_js
    prefer_focus_view # these tests drive the full-screen slide (Focus view)
    find(".ui-appbar button[data-action~='presentation#start']").click
    assert_selector ".ps-root.is-preaching"
    assert_selector ".ps-preach-offline[data-state='ready']", wait: 20
  end

  def open_projector(query = "output=1&pane=0")
    operator = current_window
    projector = open_new_window
    within_window(projector) do
      visit "#{study_path(@study)}?#{query}"
      assert_selector ".ps-root.is-output .ps-verse.is-preach-current"
    end
    switch_to_window(operator)
    projector
  end

  def wait_for_cached(path)
    Timeout.timeout(20) do
      sleep 0.2 until page.evaluate_async_script(<<~JS, path)
        const [path, done] = arguments
        caches.match(new URL(path, location.origin).href).then(r => done(!!r), () => done(false))
      JS
    end
  end

  def open_stage
    operator = current_window
    stage = open_new_window
    within_window(stage) do
      visit "#{study_path(@study)}?stage=1"
      assert_selector ".ps-root.is-stage .ps-stage"
    end
    switch_to_window(operator)
    stage
  end

  def wait_until(timeout: 30)
    Timeout.timeout(timeout) { sleep 0.2 until yield }
  end

  def shot(name)
    page.save_screenshot(File.join(SHOTS, "#{name}.png")) if SHOTS
  end
end
