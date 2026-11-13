require "application_system_test_case"

# A tester (desktop Chrome, 1366-wide laptop) couldn't scroll the Offline
# Bibles page at all — wheel, scrollbar and keys did nothing, and the list of
# Bibles was cut off at the bottom (he zoomed the browser to 25% to see it).
# The legacy .ps-root artboard (height 100vh, overflow hidden) clipped the
# page. The More sheet he came from looked cut off too: the keyboard was left
# on the button behind it, so Page Down / End scrolled nothing.
class PageScrollTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @user.update!(tour_completed_at: Time.current)
    %w[KJV ASV BSB WEB LSV YLT DBY WEBBE].each_with_index do |code, i|
      Translation.create!(code:, name: "#{code} Bible #{i}")
    end
    @study = @user.studies.create!(name: "Sunday", pane_count: 1)
    page.driver.browser.manage.window.resize_to(1366, 600)
  end

  teardown do
    page.driver.browser.manage.window.resize_to(1400, 1000)
  end

  test "More sheet → Offline Bibles: the sheet's last item is reachable and the page scrolls" do
    sign_in
    visit study_path(@study)
    wait_for_reader_js

    find(".ui-appbar [data-sheets-id-param='more']").click
    assert_selector ".ui-more-sheet.is-open"
    body = find(".ui-more-sheet .ui-sheet-body")
    assert_operator body.evaluate_script("this.scrollHeight"), :>, body.evaluate_script("this.clientHeight"),
                    "the sheet should be taller than the window here (else this test proves nothing)"
    last = all(".ui-more-sheet .ui-sheet-body .ui-menu-item, .ui-more-sheet .ui-sheet-body .ui-tile").last
    refute fully_visible_in_panel?(last), "the last item already shows: nothing to scroll"

    # The keyboard scrolls the sheet (focus is inside it, not on the button behind it).
    assert_selector ".ui-more-sheet .ui-sheet-body:focus", wait: 1
    page.send_keys(:end)
    assert wait_until { fully_visible_in_panel?(last) }, "End didn't bring the sheet's last item into view"

    # The wheel too (from the top).
    body.execute_script("this.scrollTop = 0")
    body.scroll_to(:bottom)
    assert wait_until { fully_visible_in_panel?(last) }, "the sheet's last item can't be scrolled into view"

    click_on "Offline Bibles"
    assert_current_path(/\/offline/)
    assert_selector ".ui-offline-row", minimum: 8
    refute page.evaluate_script("document.documentElement.classList.contains('ui-scroll-lock')"),
           "the More sheet's scroll lock outlived the visit"
    assert_operator page.evaluate_script("document.documentElement.scrollHeight"), :>, page.evaluate_script("innerHeight"),
                    "the page is clipped to the window"

    # Keyboard: End (no text field focused) scrolls the window.
    find("body").click
    page.send_keys(:end)
    last_row = all(".ui-offline-row").last
    assert wait_until { page.evaluate_script("window.scrollY") > 0 && last_row.evaluate_script("this.getBoundingClientRect().bottom <= innerHeight + 1") },
           "End didn't scroll the page to its last Bible"

    # …and back up with Home; the wheel works too.
    page.send_keys(:home)
    assert wait_until { page.evaluate_script("window.scrollY").zero? }
    page.scroll_to(:bottom)
    assert wait_until { page.evaluate_script("window.scrollY") > 0 }
  end

  private

  def fully_visible_in_panel?(el)
    el.evaluate_script(<<~JS)
      (() => {
        const panel = this.closest(".ui-sheet-panel").getBoundingClientRect()
        const r = this.getBoundingClientRect()
        return r.top >= panel.top - 1 && r.bottom <= panel.bottom + 1 && r.bottom <= innerHeight + 1
      })()
    JS
  end

  # true once the block is (within the timeout), else false.
  def wait_until(timeout: 3)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until yield
      return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.05
    end
    true
  end

  def sign_in
    visit new_session_path
    fill_in "email_address", with: @user.email_address
    fill_in "password", with: "password"
    click_on "Sign In"
    assert_no_current_path new_session_path
  end
end
