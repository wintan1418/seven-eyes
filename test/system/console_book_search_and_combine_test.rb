require "application_system_test_case"

# Two things a church operator (coming from EasyWorship) asked for in the
# console, mid-sermon:
#   1. search the words inside ONE book — "heb heavenly jerusalem" — fast;
#   2. put Revelation 13:1 and 13:11 (the two beasts) on ONE slide, edit the
#      words and emphasise some for the preacher; and Copy a scripture.
class ConsoleBookSearchAndCombineTest < ApplicationSystemTestCase
  include OfflineTestHelper

  SHOTS = ENV["CONSOLE_SCREENSHOTS"].presence

  BEAST_1 = "And I stood upon the sand of the sea, and saw a beast rise up out of the sea, having seven heads and ten horns, and upon his horns ten crowns, and upon his heads the name of blasphemy."
  BEAST_11 = "And I beheld another beast coming up out of the earth; and he had two horns like a lamb, and he spake as a dragon."

  setup do
    clear_offline_data
    @user = users(:one)
    @user.update!(tour_completed_at: Time.current)
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    heb = Book.create!(osis_code: "Heb", name: "Hebrews", testament: :new, position: 58, chapter_count: 13)
    rev = Book.create!(osis_code: "Rev", name: "Revelation", testament: :new, position: 66, chapter_count: 22)
    {
      [ heb, 11, 16 ] => "But now they desire a better country, that is, an heavenly: wherefore God is not ashamed to be called their God: for he hath prepared for them a city.",
      [ heb, 12, 22 ] => "But ye are come unto mount Sion, and unto the city of the living God, the heavenly Jerusalem, and to an innumerable company of angels,",
      [ rev, 13, 1 ] => BEAST_1,
      [ rev, 13, 2 ] => "And the beast which I saw was like unto a leopard,",
      [ rev, 13, 11 ] => BEAST_11,
      [ rev, 21, 2 ] => "And I John saw the holy city, new Jerusalem, coming down from God out of heaven, prepared as a bride adorned for her husband.",
      [ rev, 21, 10 ] => "and shewed me that great city, the holy Jerusalem, descending out of heaven from God,"
    }.each { |(book, c, v), text| Verse.create!(translation: @kjv, book:, chapter: c, verse_number: v, text:) }
    @study = @user.studies.create!(name: "Sunday Service", pane_count: 1)
    @study.panes.first.update!(reference: "Revelation 21:2", translation: @kjv)
    @study.setlist_items.create!(kind: :scripture, reference: "Revelation 13:1", position: 0)
    @study.setlist_items.create!(kind: :scripture, reference: "Revelation 13:2", position: 1)
    @study.setlist_items.create!(kind: :scripture, reference: "Revelation 13:11", position: 2)
  end

  teardown do
    go_online
    clear_offline_data
  end

  test "typing a book first searches the words in that book only; the chip or Esc widens it" do
    start_preaching
    box = find(".cx-find-input")
    box.set("heb heavenly jerusalem")
    assert_selector ".cx-book-chip", text: "Hebrews"
    assert_selector ".ps-verse-list[data-mode='search'][data-book='Heb'] .vrow .ref", text: "Hebrews 12:22"
    assert_no_selector ".ps-verse-list[data-mode='search'] .vrow .ref", text: /Revelation/
    assert_selector ".ps-verse-list[data-mode='search'] .ttl", text: /in Hebrews/
    shot "book-search"

    # Enter previews the first verse with every word; the screen doesn't change.
    box.send_keys(:enter)
    assert_selector "[data-preview-target='previewLabel']", text: "Hebrews 12:22"
    assert_selector "[data-console-live-target='listTitle'], .cx-live", text: /Revelation 21/i

    # A colon says it outright, and forgives a typo.
    box = find(".cx-find-input")
    box.set("hebrwes: jerusalem")
    assert_selector ".cx-book-chip", text: "Hebrews"
    assert_selector ".ps-verse-list[data-mode='search'][data-book='Heb'] .vrow .ref", text: "Hebrews 12:22"

    # × on the chip: every book, the words kept.
    find(".cx-book-chip").execute_script("this.click()")
    assert_field class: "cx-find-input", with: "jerusalem"
    assert_selector ".cx-book-chip", visible: :hidden
    assert_selector ".ps-verse-list[data-mode='search'] .vrow .ref", text: "Revelation 21:2"
  end

  test "the book picker: This book searches the book on screen, arrows walk the matches" do
    start_preaching
    picker = find("[data-console-library-target='book']")
    assert_selector "option[value='live']", text: "This book — Revelation", visible: :all
    picker.select("This book — Revelation")
    box = find(".cx-find-input")
    box.set("jerusalem")
    assert_selector ".cx-book-chip", text: "Revelation"
    assert_selector ".ps-verse-list[data-mode='search'][data-book='Rev'][data-query='jerusalem'] .vrow", count: 2
    assert_no_selector ".ps-verse-list[data-mode='search'] .vrow .ref", text: /Hebrews/
    # Keyboard: ↓ into the list, ↓ to the second match, Enter previews it.
    box.send_keys(:down)
    page.send_keys(:down)
    page.send_keys(:enter)
    assert_selector "[data-preview-target='previewLabel']", text: "Revelation 21:10"
    # Esc in the box drops the book.
    find(".cx-find-input").send_keys(:escape)
    assert_equal "", find("[data-console-library-target='book']").value
    assert_selector ".ps-verse-list[data-mode='search'] .vrow .ref", text: "Hebrews 12:22"
  end

  test "pick two queued scriptures, combine them into one slide, emphasise words, go live" do
    start_preaching
    projector = open_projector

    queue_row(/Revelation 13:1\z/).click
    # Shift+click picks the run; Ctrl/⌘+click takes 13:2 out again.
    queue_row(/Revelation 13:11\z/).click(:shift)
    assert_selector ".ps-pickbar .n", text: "3 picked"
    ctrl_click queue_row(/Revelation 13:2\z/)
    assert_selector ".ps-pickbar .n", text: "2 picked"
    assert_selector ".ps-setlist-item.is-picked", count: 2
    shot "combine-picked"

    click_on "Combine into one slide"
    within(".ps-tool-dialog[aria-label='Combine into one slide']") do
      assert_field "cb-label", with: "Revelation 13:1, 11"
      assert_field "cb-text", with: "1 #{BEAST_1}\n11 #{BEAST_11}"
      assert_selector ".set-screen .set-ref", text: /Revelation 13:1, 11 \(KJV\)/i
      select_in_text("seven heads")
      click_on "Bold"
      select_in_text("another beast")
      find(".cb-mark.is-hl").click
      assert_selector ".set-screen .set-em", text: "seven heads"
      assert_selector ".set-screen .set-hl", text: "another beast"
      assert_includes find("#cb-text").value, "**seven heads**"
      # Edited words go to the screen as typed.
      page.execute_script("const a = document.querySelector('#cb-text'); a.focus(); a.setSelectionRange(a.value.length, a.value.length)")
      find("#cb-text").send_keys(" (the false prophet)")
      assert_selector ".set-screen .set-words", text: "the false prophet"
      shot "combine-dialog"
      click_on "Add to service"
    end
    assert_no_selector ".ps-tool-dialog[aria-label='Combine into one slide']"

    # Saved in the service as one slide, and waiting in Preview.
    assert_selector ".ps-setlist-item .present .lbl", text: "Revelation 13:1, 11 KJV"
    assert_selector "[data-preview-target='previewLabel']", text: "Revelation 13:1, 11 KJV"
    assert_no_selector ".ps-pickbar", visible: true
    find("body").send_keys("l")
    assert_selector ".ps-root.is-slide .ps-preach-slide .set-ref", text: /Revelation 13:1, 11 \(KJV\)/i
    assert_selector ".ps-preach-slide .set-em", text: "seven heads"
    assert_selector ".ps-preach-slide .set-hl", text: "another beast"
    within_window(projector) do
      assert_selector ".ps-preach-slide .set-hl", text: "another beast"
      assert_selector ".ps-preach-slide .set-words", text: "the false prophet"
      assert_no_text "**"
    end
    shot "combine-live"

    # It syncs like any queue item, emphasis and all.
    wait_until { @study.setlist_items.where(kind: :scripture_set).exists? }
    item = @study.setlist_items.find_by(kind: :scripture_set)
    assert item.data["combined"]
    assert_equal "one", item.data["split"]
    assert_equal [ 1, 11 ], item.data["refs"][0]["verses"].map { |v| v["n"] }
    assert_includes item.data["refs"][0]["verses"][1]["text"], "==another beast=="
    assert_no_match(/\*\*|==/, item.body)

    # ✎ opens the same editor again.
    find(".ps-setlist-item.kind-scripture_set").hover
    find(".ps-setlist-item.kind-scripture_set .op", text: "✎").click
    within(".ps-tool-dialog[aria-label='Combine into one slide']") do
      assert_includes find("#cb-text").value, "==another beast=="
      assert_selector "button", text: "Save changes"
    end
  end

  test "Copy puts the verses and their reference on the clipboard" do
    start_preaching
    stub_clipboard
    queue_row(/Revelation 13:1\z/).click
    queue_row(/Revelation 13:2\z/).click(:shift)
    within(".ps-pickbar") { click_on "Copy" }
    assert_selector ".ps-queue-toast", text: /Copied Revelation 13:1-2 \(KJV\)/
    assert_equal "Revelation 13:1-2 (KJV)\n1 #{BEAST_1}\n2 And the beast which I saw was like unto a leopard,", page.evaluate_script("window.__copied")

    # And what is in Preview, from its own Copy.
    queue_row(/Revelation 13:11\z/).click
    assert_selector "[data-preview-target='previewLabel']", text: "Revelation 13:11"
    find("[data-preview-target='copyPreview']").click
    assert_selector "[data-preview-target='copyPreview']", text: "Copied"
    assert_equal "Revelation 13:11 (KJV)\n11 #{BEAST_11}", page.evaluate_script("window.__copied")
  end

  private

  # The row's number: clear of the ✎ ↑ ↓ ✕ buttons that show on hover.
  def queue_row(label)
    find(".ps-setlist-item .present", text: label).find(".num")
  end

  # Ctrl+click (⌘ on a Mac). Dispatched: headless Chrome on a Mac drops some
  # modifier clicks, and what matters here is what the queue does with one.
  def ctrl_click(node)
    node.execute_script("this.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, ctrlKey: true }))")
  end

  def select_in_text(words)
    page.execute_script(<<~JS, words)
      const area = document.querySelector("#cb-text")
      const i = area.value.indexOf(arguments[0])
      area.focus()
      area.setSelectionRange(i, i + arguments[0].length)
    JS
  end

  def stub_clipboard
    page.execute_script(<<~JS)
      window.__copied = null
      Object.defineProperty(navigator, "clipboard", { configurable: true, value: { writeText: async (t) => { window.__copied = t } } })
    JS
  end

  def wait_until(timeout: 15)
    Timeout.timeout(timeout) { sleep 0.2 until yield }
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
    mark_console_tour_seen
    find(".ui-appbar button[data-action~='presentation#start']").click
    assert_selector ".ps-root.is-preaching.is-console"
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

  def shot(name)
    page.save_screenshot(File.join(SHOTS, "#{name}.png")) if SHOTS
  end
end
