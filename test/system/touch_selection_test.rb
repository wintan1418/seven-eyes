require "application_system_test_case"

# The phone path for highlights / Rabbi / Share: select words by long-press and
# Bibliorata's own action bar must appear at the bottom of the screen alongside
# the browser's native Copy/Select-all menu. Emulates an Android phone (touch,
# coarse pointer) and replays Chrome Android's long-press sequence — touch down,
# the browser selects the word under the finger, contextmenu, finger up —
# since headless Chrome doesn't turn a raw touch hold into a gesture itself.
class TouchSelectionTest < ApplicationSystemTestCase
  # A driver name of its own: under the shared :selenium name, whichever test
  # class registered last won and the phone emulation leaked or went missing
  # depending on test order.
  driven_by :selenium, using: :headless_chrome, screen_size: [ 412, 915 ], options: { name: :selenium_pixel } do |opts|
    opts.add_emulation(device_name: "Pixel 7")
    # With mobile emulation set, chromedriver isn't handed the Selenium-managed
    # Chrome automatically (it is for the default driver); ask Selenium Manager
    # directly. On a machine with a system Chrome this is a no-op.
    path = begin
      Selenium::WebDriver::SeleniumManager.binary_paths("--browser", "chrome")["browser_path"]
    rescue StandardError
      nil
    end
    opts.binary = path if path.present?
  end

  VERSE = ".ps-verse[data-verse-num='26'] .ps-verse-text".freeze

  setup do
    kjv = Translation.create!(code: "KJV", name: "King James Version")
    jer = Book.create!(osis_code: "Jer", name: "Jeremiah", testament: :old, position: 24, chapter_count: 52)
    tokens = [ { "w" => "Behold", "s" => "H2005" }, { "w" => ", I am against thee, O destroying " },
               { "w" => "mountain", "s" => "H2022" }, { "w" => ", saith the LORD." } ]
    Verse.create!(translation: kjv, book: jer, chapter: 51, verse_number: 25, tokens: tokens,
                  text: "Behold, I am against thee, O destroying mountain, saith the LORD.")
    Verse.create!(translation: kjv, book: jer, chapter: 51, verse_number: 26,
                  text: "And they shall not take of thee a stone for a corner, nor a stone for foundations.")
  end

  test "long-pressing a verse on a phone raises the selection bar, which outlives a stray touch" do
    open_passage
    assert page.evaluate_script("matchMedia('(any-pointer: coarse)').matches"), "emulation should report a coarse pointer"

    long_press_select(VERSE, 0, 3)
    assert_selector ".ps-hl-popover.is-touch-bar", text: /rabbi/i, wait: 2
    assert_selector ".ps-hl-popover.is-touch-bar .ps-hl-swatch", count: 4
    rect = page.evaluate_script("(() => { const r = document.querySelector('.ps-hl-popover').getBoundingClientRect(); return [r.top, r.bottom, innerHeight] })()")
    assert rect[1] <= rect[2], "the bar should sit inside the viewport"

    # A stray pointerdown elsewhere (nudging a selection handle, steadying the
    # phone) while the words stay selected must not dismiss the bar.
    page.execute_script("document.body.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true, pointerType: 'touch' }))")
    sleep 0.5
    assert_selector ".ps-hl-popover.is-touch-bar"
    assert_equal "And", page.evaluate_script("getSelection().toString()")

    # A real tap elsewhere clears the selection, and the bar goes with it.
    tap(20, 400)
    assert_no_selector ".ps-hl-popover", wait: 2
  end

  test "the bar appears even if selectionchange never fires (touchend fallback)" do
    open_passage
    page.execute_script(<<~JS)
      // Simulate a browser that selects silently: suppress selectionchange reaching the page.
      document.addEventListener("selectionchange", e => e.stopImmediatePropagation(), true)
    JS
    long_press_select(VERSE, 0, 3)
    assert_selector ".ps-hl-popover.is-touch-bar", wait: 2
  end

  private

  def open_passage
    visit root_path
    # A fresh guest gets the guided tour; it would sit over the verses.
    page.execute_script("localStorage.setItem('scriptorium.tourDone', '1')")
    fill_in "reference", with: "Jeremiah 51:25-26"
    click_on "Read"
    assert_selector ".ps-verse", minimum: 2
  end

  def cdp(method, **params) = page.driver.browser.execute_cdp(method, **params)

  def tap(x, y)
    cdp("Input.dispatchTouchEvent", type: "touchStart", touchPoints: [ { x: x, y: y } ])
    cdp("Input.dispatchTouchEvent", type: "touchEnd", touchPoints: [])
  end

  def long_press_select(selector, from, to)
    x, y = page.evaluate_script("(() => { const r = document.querySelector(#{selector.to_json}).getBoundingClientRect(); return [r.left + 40, r.top + 12] })()")
    cdp("Input.dispatchTouchEvent", type: "touchStart", touchPoints: [ { x: x, y: y } ])
    sleep 0.5
    page.execute_script(<<~JS)
      const el = document.querySelector(#{selector.to_json});
      const r = document.createRange(); r.setStart(el.firstChild, #{from}); r.setEnd(el.firstChild, #{to});
      const sel = getSelection(); sel.removeAllRanges(); sel.addRange(r);
      el.dispatchEvent(new MouseEvent("contextmenu", { bubbles: true, cancelable: true }));
    JS
    sleep 0.2
    cdp("Input.dispatchTouchEvent", type: "touchEnd", touchPoints: [])
  end
end
