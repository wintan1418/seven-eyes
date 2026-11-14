require "application_system_test_case"
require_relative "../test_helpers/today_seed"

# Pastor mode on a phone: This Sunday is a compact card — title, date, one
# summary line, the three buttons — with the order of service folded away
# until asked for. Laptops show the whole card.
class PastorHomePhoneTest < ApplicationSystemTestCase
  include TodaySeed

  setup do
    seed_today!
    Book.create!(osis_code: "Jer", name: "Jeremiah", testament: :old, position: 24, chapter_count: 52)
    @study = users(:one).studies.create!(name: "The Potter's House", pane_count: 1, last_opened_at: 1.hour.ago)
    @study.setlist_items.create!(kind: :scripture, reference: "Jeremiah 18:1-6")
    3.times { |i| @study.setlist_items.create!(kind: :song, title: "Song #{i}", body: "Words") }
  end

  teardown { page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride") }

  test "on a phone This Sunday is a compact card and the order of service folds out" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 2, mobile: true)
    sign_in

    within(".hm-sunday") do
      assert_selector ".hm-sunday-title", text: "The Potter's House"
      assert_selector ".hm-sunday-brief", text: /4 items.*1 to do/m
      assert_link "Present", visible: true
      assert_link "Open service", visible: true
      assert_link "Get ready", visible: true
      assert_no_selector ".hm-sunday-item", visible: true
      assert_no_selector ".hm-sunday-checks", visible: true
      # The three buttons sit on one row.
      rows = all(".hm-sunday-btn").map { |b| b.rect.y.round }
      assert_equal 1, rows.uniq.size
    end
    height = find(".hm-sunday").rect.height
    assert_operator height, :<, 844 * 0.45, "the card is #{height}px tall; it should leave room for Today"

    find(".hm-sunday-fold").click
    within(".hm-sunday") do
      assert_selector ".hm-sunday-fold[aria-expanded='true']"
      assert_selector ".hm-sunday-item", count: 4, visible: true
      assert_selector ".hm-sunday-checks .is-todo", text: /3 songs have no order yet/, visible: true
    end
    find(".hm-sunday-fold").click
    assert_no_selector ".hm-sunday-item", visible: true
  end

  test "a laptop shows the whole card, no fold" do
    sign_in
    within(".hm-sunday") do
      assert_selector ".hm-sunday-item", count: 4, visible: true
      assert_selector ".hm-sunday-checks", visible: true
      assert_no_selector ".hm-sunday-fold", visible: true
    end
  end

  private

  def sign_in
    visit new_session_path
    fill_in "email_address", with: users(:one).email_address
    fill_in "password", with: "password"
    click_on "Sign In"
    assert_selector ".hm-sunday"
  end
end
