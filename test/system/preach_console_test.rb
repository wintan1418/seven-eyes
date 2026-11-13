require "application_system_test_case"

# The operator console: preach mode's default layout on a church laptop. A
# media volunteer coming from EasyWorship found the old single column
# confusing — the slide filled the screen and everything else was stacked in
# one narrow strip he had to scroll. Now: the service list on the left,
# Preview and Live side by side, a tabbed library along the bottom, one
# toolbar on top — nothing important below the fold at 1366×768. The
# full-screen slide is still there as Focus (F).
class PreachConsoleTest < ApplicationSystemTestCase
  include OfflineTestHelper

  SHOTS = ENV["CONSOLE_SCREENSHOTS"].presence

  JOHN_3 = {
    14 => "And as Moses lifted up the serpent in the wilderness, even so must the Son of man be lifted up:",
    15 => "That whosoever believeth in him should not perish, but have eternal life.",
    16 => "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.",
    17 => "For God sent not his Son into the world to condemn the world; but that the world through him might be saved.",
    18 => "He that believeth on him is not condemned: but he that believeth not is condemned already, because he hath not believed in the name of the only begotten Son of God.",
    19 => "And this is the condemnation, that light is come into the world, and men loved darkness rather than light, because their deeds were evil.",
    20 => "For every one that doeth evil hateth the light, neither cometh to the light, lest his deeds should be reproved.",
    21 => "But he that doeth truth cometh to the light, that his deeds may be made manifest, that they are wrought in God."
  }.freeze
  PSALM_23 = {
    1 => "The LORD is my shepherd; I shall not want.",
    2 => "He maketh me to lie down in green pastures: he leadeth me beside the still waters.",
    3 => "He restoreth my soul: he leadeth me in the paths of righteousness for his name's sake.",
    4 => "Yea, though I walk through the valley of the shadow of death, I will fear no evil: for thou art with me; thy rod and thy staff they comfort me."
  }.freeze

  setup do
    clear_offline_data
    @user = users(:one)
    @user.update!(tour_completed_at: Time.current)
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    psalms = Book.create!(osis_code: "Ps", name: "Psalms", testament: :old, position: 19, chapter_count: 150)
    JOHN_3.each { |v, text| Verse.create!(translation: @kjv, book: john, chapter: 3, verse_number: v, text:) }
    PSALM_23.each { |v, text| Verse.create!(translation: @kjv, book: psalms, chapter: 23, verse_number: v, text:) }
    @study = @user.studies.create!(name: "Sunday Service", pane_count: 1)
    @study.panes.first.update!(reference: "John 3:16", translation: @kjv)
    grace = Hymnal::HYMNS.find { |h| h[:title] == "Amazing Grace" || h["title"] == "Amazing Grace" }
    @grace_body = grace[:body] || grace["body"]
    [
      { kind: :thought, title: "Welcome", body: "Welcome to the house of the Lord\n\nPlease silence your phones" },
      { kind: :song, title: "Amazing Grace", body: @grace_body },
      { kind: :scripture, reference: "Psalm 23:1-4" },
      { kind: :scripture, reference: "John 3:16" }
    ].each.with_index { |attrs, i| @study.setlist_items.create!(attrs.merge(position: i)) }
  end

  teardown do
    page.driver.browser.manage.window.resize_to(1400, 1000)
    go_online
    clear_offline_data
  end

  test "on a 1366×768 laptop the console is the default and everything is on screen at once" do
    resize_to(1366, 768)
    start_preaching
    assert_selector ".ps-root.is-console"
    assert_regions_on_screen(1366, 768)

    # The service: every item, its type icon and the Preview / Live / Next marks.
    within(".ps-setlist-items") do
      assert_selector ".ps-setlist-item", count: 4
      assert_selector ".ps-setlist-item.kind-song .icon", text: "♫"
    end
    # Live shows the passage the study opened on; the toolbar says so in words.
    assert_selector ".cx-state[data-cx-state='live'] .cx-state-word", text: /live/i
    assert_selector ".cx-state-what", text: "John 3:16"
    assert_selector ".cx-live-list .cx-line.is-live", text: "For God so loved the world"
    assert_selector ".cx-mini[data-kind='empty'] .cx-mini-empty", text: /John 3:16/

    # Preview a song from the service: the miniature shows its first slide,
    # its slides list below, and nothing changes on the big screen.
    find(".ps-setlist-item", text: "Amazing Grace").find(".present").click
    assert_selector ".cx-mini[data-kind='slide'] .cx-mini-words", text: /Amazing grace/i
    assert_selector ".ps-console-preview .ps-preview-text .slide", minimum: 4
    assert_selector ".ps-setlist-item.is-preview", text: "Amazing Grace"
    assert_selector ".ps-pane.is-presented .ps-verse.is-preach-current[data-verse-num='16']"
    assert_no_selector ".ps-root.is-slide"
    shot "1366-console-song-in-preview"

    # Black: the toolbar and the Live miniature say so in words.
    press(".")
    assert_selector ".cx-state[data-cx-state='black'] .cx-state-word", text: /black/i
    assert_selector ".cx-screen-veil[data-mode='black']", text: /black/i
    shot "1366-black"
    press(".")
    assert_selector ".cx-state[data-cx-state='live']"
    assert_no_selector ".cx-screen-veil", visible: true

    # Go live from the toolbar.
    find(".ps-preach-bar .cx-golive").click
    assert_selector ".ps-root.is-slide [data-preach-slide] .slide-stanza", text: /Amazing grace/i
    assert_selector ".cx-state-what", text: "Amazing Grace"
    assert_selector ".cx-live-list .cx-line", minimum: 4
    assert_selector ".cx-live-list .cx-line.is-live[data-n='0']"
    assert_selector ".ps-setlist-item.is-live", text: "Amazing Grace"

    # A line of the live list puts that slide up.
    find(".cx-live-list .cx-line[data-n='2'] .pick").click
    assert_selector ".cx-live-list .cx-line.is-live[data-n='2']"
    press(:left)
    assert_selector ".cx-live-list .cx-line.is-live[data-n='1']"
  end

  test "the library: type a reference, preview, go live; the Songs tab previews a hymn" do
    resize_to(1366, 768)
    start_preaching

    find(".cx-find-input").fill_in(with: "ps 23")
    assert_selector ".ps-verse-list .vrow", count: 4
    assert_selector ".ps-verse-list .ttl", text: "Psalms 23"
    find(".cx-find-input").send_keys("")
    find(".cx-find-input").fill_in(with: "ps 23:2")
    find(".cx-find-input").send_keys(:enter)
    assert_selector ".ps-console-preview[data-state='ready'] .what", text: "Psalms 23:2"
    assert_selector ".cx-mini[data-kind='scripture'] .cx-mini-words", text: "green pastures"
    assert_selector ".cx-mini-ref", text: /Psalms 23:2/i
    assert_selector ".ps-pane.is-presented .ps-verse.is-preach-current[data-osis='John']" # not on screen yet

    # Double-click a verse in the list: straight to the screen.
    find(".ps-verse-list .vrow[data-num='1'] .pick").double_click
    assert_selector ".ps-pane.is-presented .ps-verse.is-preach-current[data-osis='Ps'][data-verse-num='1']", wait: 5
    assert_selector ".cx-state-what", text: "Psalms 23:1"
    # Next from the toolbar walks the passage.
    find(".ps-preach-bar-right [data-action~='presentation#next']").click
    assert_selector ".ps-pane.is-presented .ps-verse.is-preach-current[data-verse-num='2']"
    assert_selector ".cx-live-list .cx-line.is-live[data-n='2']"

    # Songs: the song bank sits in the library, not a dialog over everything.
    find(".cx-tab[data-tab='songs']").click
    assert_selector ".ps-root[data-cx-tab='songs'] .ps-song-bank .bank-row", minimum: 1, wait: 10
    assert_no_selector ".ps-song-bank .bank-head", visible: true
    find(".ps-song-bank .bank-search").fill_in(with: "amazing grace")
    find(".ps-song-bank .bank-row", text: "Amazing Grace", match: :first).click
    assert_selector ".ps-console-preview .what", text: "Amazing Grace"
    assert_selector ".cx-mini[data-kind='slide'] .cx-mini-words", text: /Amazing grace/i
    shot "1366-songs-tab"

    # Looks: the screen panel lives in its tab.
    find(".cx-tab[data-tab='looks']").click
    assert_selector ".ps-screen-panel .ps-look-tile[data-look-id='royal']"
    # Presentations: the slide tools.
    find(".cx-tab[data-tab='presentations']").click
    assert_selector ".cx-launch-card", text: "Import a presentation"
    assert_selector ".cx-launch-card", text: "Build seminar slides"
    find(".cx-launch-card", text: "Build seminar slides").click
    assert_selector ".ps-tool-dialog[aria-label='Seminar slides']", visible: true
    find(".ps-tool-dialog[aria-label='Seminar slides'] .close").click

    # Word study: W opens the root-word card in its tab; closing it goes back.
    find(".cx-tab[data-tab='scripture']").click
    press("w")
    assert_selector ".ps-root[data-cx-tab='words'] .rw-card", visible: true
    card = find(".rw-card").evaluate_script("(r => [r.top, r.bottom])(this.getBoundingClientRect())")
    lib = find(".cx-library").evaluate_script("(r => [r.top, r.bottom])(this.getBoundingClientRect())")
    assert card[0] >= lib[0] && card[1] <= lib[1] + 1, "the card sits in the library: #{card.inspect} vs #{lib.inspect}"
    find(".rw-card [data-action~='root-words#close']").click
    assert_selector ".ps-root[data-cx-tab='scripture']"
  end

  test "the church's own picture shows in the Preview miniature and on every look thumbnail" do
    resize_to(1366, 768)
    start_preaching

    find(".cx-find-input").fill_in(with: "ps 23:2")
    find(".cx-find-input").send_keys(:enter)
    assert_selector ".cx-mini[data-kind='scripture'] .cx-mini-words", text: "green pastures"
    assert_no_selector ".cx-mini-bg .media", visible: :all

    find(".cx-tab[data-tab='looks']").click
    picture = Rails.root.join("public/icon.png")
    find("input[type='file'][data-slot='image']", visible: :all).attach_file(picture, make_visible: true)

    assert_selector ".ps-root[data-look-bg='image']", wait: 5
    assert_selector ".cx-mini-bg img.media", visible: :all, wait: 5
    assert_selector ".ps-look-preview .lp-bg img.media", visible: :all
    assert_selector ".ps-look-tile .lt-bg img.media", visible: :all, minimum: 2
    # The words stay above the picture.
    on_top = find(".cx-mini-words").evaluate_script(<<~JS)
      (el => { const r = el.getBoundingClientRect(); const hit = document.elementFromPoint(r.left + r.width / 2, r.top + 4); return el.contains(hit) || hit === el })(this)
    JS
    assert on_top, "the Preview words sit above the background"
    shot "1366-own-picture"

    # Back to the look's own background: the picture leaves every miniature.
    find("[data-screen-look-target='bgButton'][data-bg='look']").click
    assert_no_selector ".cx-mini-bg .media", visible: :all, wait: 5
    assert_no_selector ".ps-look-tile .lt-bg .media", visible: :all
  end

  test "Focus is the full-screen slide, remembered, and F switches back" do
    resize_to(1366, 768)
    start_preaching
    assert_selector ".ps-root.is-console"
    press("f")
    assert_no_selector ".ps-root.is-console"
    assert_selector ".ps-preach-bar .cx-view-toggle [data-cx-view-label]", text: /console/i
    bar = find(".ps-preach-bar").evaluate_script("this.getBoundingClientRect().bottom")
    assert_in_delta 768, bar, 2, "the bar is back along the bottom"
    assert_no_selector ".cx-service", visible: true
    shot "1366-focus"

    # Remembered for the next service.
    visit study_path(@study)
    wait_for_reader_js
    find(".ui-appbar button[data-action~='presentation#start']").click
    assert_selector ".ps-root.is-preaching"
    assert_no_selector ".ps-root.is-console"
    find(".ps-preach-bar .cx-view-toggle").click
    assert_selector ".ps-root.is-console"
  end

  test "the add buttons open the form in a card; Esc closes it and never leaves preach mode" do
    resize_to(1366, 768)
    start_preaching
    assert_no_selector ".ps-setlist-form", visible: true
    find(".cx-add-btn.is-scripture").click
    assert_selector ".cx-addcard", text: /add scriptures to the service/i
    find(".ps-setlist-form .ref-field").send_keys("John 3:17", :enter)
    assert_selector ".ps-setlist-item", text: "John 3:17"
    find(".ps-setlist-form .ref-field").send_keys(:escape)
    assert_no_selector ".cx-addcard", visible: true
    assert_selector ".ps-root.is-preaching.is-console"

    find(".cx-add-btn.is-song").click
    assert_selector ".ps-setlist-form.kind-song .title-field:focus"
    find(".cx-addcard .cx-close").click
    assert_no_selector ".ps-setlist-form", visible: true
  end

  test "first run: a four-step tour, shown once" do
    resize_to(1366, 768)
    start_preaching(tour: true)
    assert_selector ".cx-tour .cx-tour-title", text: "The service", wait: 3
    shot "1366-tour"
    find(".cx-tour-next").click
    assert_selector ".cx-tour .cx-tour-title", text: "Preview"
    press(:right) # the arrow keys walk it too (and never reach the projector)
    assert_selector ".cx-tour .cx-tour-title", text: "Live"
    find(".cx-tour-next").click
    assert_selector ".cx-tour .cx-tour-title", text: "library"
    assert_selector ".cx-tour-next", text: "Got it"
    find(".cx-tour-next").click
    assert_no_selector ".cx-tour", visible: true

    visit study_path(@study)
    wait_for_reader_js
    find(".ui-appbar button[data-action~='presentation#start']").click
    assert_selector ".ps-root.is-console"
    sleep 0.8
    assert_no_selector ".cx-tour", visible: true
    # "? Tour" replays it.
    find(".ps-preach-bar [data-action~='console#tour']").click
    assert_selector ".cx-tour .cx-tour-title", text: "The service"
    press(:escape)
    assert_no_selector ".cx-tour", visible: true
    assert_selector ".ps-root.is-preaching"
  end

  test "1920×1080 and a tablet-sized window" do
    resize_to(1920, 1080)
    start_preaching
    assert_regions_on_screen(1920, 1080)
    find(".ps-setlist-item", text: "John 3:16").find(".present").double_click
    find(".ps-setlist-item", text: "Amazing Grace").find(".present").click
    assert_selector ".cx-mini[data-kind='slide']"
    shot "1920-console-song-in-preview"
    find(".cx-tab[data-tab='songs']").click
    assert_selector ".ps-song-bank .bank-row", minimum: 1, wait: 10
    shot "1920-songs-tab"
    find(".cx-tab[data-tab='scripture']").click
    press("f")
    assert_no_selector ".ps-root.is-console"
    shot "1920-focus"
    press("f")
    page.execute_script("window.dispatchEvent(new CustomEvent('console:tour'))")
    assert_selector ".cx-tour .cx-tour-title", text: "The service"
    shot "1920-tour"
    press(:escape)

    # A Look (slide_themes) reaches both miniatures.
    find(".cx-tab[data-tab='looks']").click
    find(".ps-screen-panel .ps-look-tile[data-look-id='royal']").click
    assert_selector ".ps-root[data-look='royal']"
    shot "1920-look-royal"

    # Narrower than a laptop: the preach mode of before, no console.
    resize_to(1060, 800)
    assert_no_selector ".ps-root.is-console"
    assert_no_selector ".ps-preach-bar .cx-view-toggle", visible: true
    shot "1060-tablet"
  end

  test "Present offline (?present=1) opens the console with the Go box ready: Enter puts the verse up" do
    resize_to(1366, 768)
    sign_in
    visit study_path(@study)
    wait_for_reader_js
    mark_console_tour_seen
    visit "#{study_path(@study)}?present=1"
    assert_selector ".ps-root.is-console .ps-preach-jump input:focus", wait: 5
    # The study's own passage lands first (preach opens a lone verse as its chapter).
    assert_selector ".ps-pane.is-presented .ps-verse.is-preach-current[data-verse-num='16']", wait: 5
    find(".ps-preach-jump input").send_keys("ps 23:4", :enter)
    assert_selector ".ps-pane.is-presented .ps-verse.is-preach-current[data-osis='Ps'][data-verse-num='4']", wait: 5
    assert_selector ".cx-state-what", text: "Psalms 23:4"
  end

  private

  # A key to whatever has focus (the page itself when nothing does).
  def press(*keys)
    page.driver.browser.action.send_keys(*keys).perform
  end

  # The viewport (what a laptop screen shows), not the outer window.
  def resize_to(width, height)
    window = page.driver.browser.manage.window
    window.resize_to(width, height)
    inner = page.evaluate_script("[innerWidth, innerHeight]")
    window.resize_to(width + (width - inner[0]), height + (height - inner[1]))
  end

  def sign_in
    visit new_session_path
    fill_in "email_address", with: @user.email_address
    fill_in "password", with: "password"
    click_on "Sign In"
    assert_no_current_path new_session_path
  end

  def start_preaching(tour: false)
    sign_in
    visit study_path(@study)
    wait_for_service_worker
    wait_for_reader_js
    mark_console_tour_seen unless tour
    find(".ui-appbar button[data-action~='presentation#start']").click
    assert_selector ".ps-root.is-preaching"
    assert_selector ".ps-preach-offline[data-state='ready']", wait: 20
  end

  def assert_regions_on_screen(width, height)
    inner = page.evaluate_script("[innerWidth, innerHeight]")
    assert_equal [ width, height ], inner, "the window should be #{width}×#{height}"
    %w[.cx-service .cx-preview .cx-live .cx-library .ps-preach-bar .cx-screen .cx-mini .cx-add .cx-tabs].each do |sel|
      r = find(sel).evaluate_script("(r => [r.left, r.top, r.right, r.bottom])(this.getBoundingClientRect())")
      assert r[0] >= 0 && r[1] >= 0 && r[2] <= width + 0.5 && r[3] <= height + 0.5, "#{sel} is off screen: #{r.inspect}"
      assert r[2] - r[0] > 40 && r[3] - r[1] > 20, "#{sel} is too small: #{r.inspect}"
    end
    # The live miniature is 16:9 and the presented pane sits on it.
    screen = find(".cx-screen").evaluate_script("(r => [r.left, r.top, r.width, r.height])(this.getBoundingClientRect())")
    assert_in_delta 16.0 / 9, screen[2] / screen[3], 0.02
    shell = find(".ps-shell").evaluate_script("(r => [r.left, r.top, r.width, r.height])(this.getBoundingClientRect())")
    screen.zip(shell).each { |a, b| assert_in_delta a, b, 1.5 }
  end

  def shot(name)
    return unless SHOTS
    sleep 0.4 # let fades finish
    page.save_screenshot(File.join(SHOTS, "#{name}.png"))
  end
end
