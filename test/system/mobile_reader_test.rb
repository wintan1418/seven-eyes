require "application_system_test_case"

# The reader on a phone (Pixel 7 emulation, like touch_selection_test): tab
# bar, bottom sheets, swipe between chapters, no sideways scrolling.
class MobileReaderTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 412, 915 ], options: { name: :selenium_pixel_reader } do |opts|
    opts.add_emulation(device_name: "Pixel 7")
    path = begin
      Selenium::WebDriver::SeleniumManager.binary_paths("--browser", "chrome")["browser_path"]
    rescue StandardError
      nil
    end
    opts.binary = path if path.present?
  end

  setup do
    kjv = Translation.create!(code: "KJV", name: "King James Version")
    bsb = Translation.create!(code: "BSB", name: "Berean Standard Bible")
    john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    (1..30).each do |v|
      Verse.create!(translation: kjv, book: john, chapter: 3, verse_number: v, text: "Chapter three verse #{v} of the Gospel of John in the King James text.")
      Verse.create!(translation: bsb, book: john, chapter: 3, verse_number: v, text: "BSB three #{v}.")
    end
    Verse.create!(translation: kjv, book: john, chapter: 4, verse_number: 1, text: "Chapter four begins here.")
  end

  test "tab bar, no sideways scroll, action bar above the tabs" do
    open_john3
    assert_selector ".ui-tabbar", visible: true
    assert_selector ".ui-tabbar .ui-tab", count: 4
    assert_equal false, page.evaluate_script("document.documentElement.scrollWidth > window.innerWidth"),
                 "the page must not scroll sideways"

    find(".ps-verse[data-verse-num='3'] .ps-verse-text").click
    assert_selector ".ui-actionbar", visible: true
    bar = rect(".ui-actionbar")
    tabs = rect(".ui-tabbar")
    assert bar["bottom"] <= tabs["top"], "the action bar must sit above the tab bar"
  end

  test "swiping left opens the next chapter" do
    open_john3
    y = 400
    cdp("Input.dispatchTouchEvent", type: "touchStart", touchPoints: [ { x: 320, y: y } ])
    cdp("Input.dispatchTouchEvent", type: "touchMove", touchPoints: [ { x: 200, y: y + 4 } ])
    cdp("Input.dispatchTouchEvent", type: "touchMove", touchPoints: [ { x: 70, y: y + 6 } ])
    cdp("Input.dispatchTouchEvent", type: "touchEnd", touchPoints: [])
    assert_selector ".ps-verse-text", text: "Chapter four begins here."
  end

  test "the passage picker is a bottom sheet; Notes tab opens the notes" do
    open_john3
    find(".ui-tabbar .ui-tab", text: "Bible").click
    assert_selector ".ui-passage-sheet.is-open"
    settle_sheet
    panel = rect(".ui-passage-sheet .ui-sheet-panel")
    assert_in_delta page.evaluate_script("window.innerHeight"), panel["bottom"], 2
    assert_in_delta 0, panel["left"], 1
    find(".ui-passage-sheet [aria-label='Close']").click
    assert_no_selector ".ui-passage-sheet.is-open"

    find(".ui-tabbar .ui-tab", text: "Notes").click
    assert_selector ".ps-notes-form.is-open"
  end

  test "Compare stacks two panes, one above the other" do
    open_john3
    find(".ui-tabbar .ui-tab", text: "More").click
    assert_selector ".ui-more-sheet.is-open"
    settle_sheet
    find(".ui-more-sheet .ui-menu-item", text: "Compare translations").click
    assert_selector ".ps-workspace .ps-pane", count: 2
    first, second = all(".ps-workspace .ps-pane").map { |p| page.evaluate_script("arguments[0].getBoundingClientRect().toJSON()", p) }
    assert second["top"] >= first["bottom"] - 1, "panes stack vertically on a phone"
    assert_in_delta first["width"], second["width"], 1
  end

  private

  def open_john3
    visit root_path
    page.execute_script("localStorage.setItem('scriptorium.tourDone', '1')")
    fill_in "reference", with: "John 3"
    click_on "Read"
    assert_selector ".ps-verse", minimum: 10
  end

  # Sheets slide up for ~0.25s; let them land before measuring or tapping.
  def settle_sheet = sleep(0.4)

  def rect(selector) = page.evaluate_script("document.querySelector(#{selector.to_json}).getBoundingClientRect().toJSON()")

  def cdp(method, **params) = page.driver.browser.execute_cdp(method, **params)
end
