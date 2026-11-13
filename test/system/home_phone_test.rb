require "application_system_test_case"

# The signed-in home on a phone was six screens long (the tools guide alone
# was ~1,900px). Phones now get the essentials, with the rest a tap away;
# laptops are unchanged.
class HomePhoneTest < ApplicationSystemTestCase
  setup do
    kjv = Translation.create!(code: "KJV", name: "King James Version")
    eph = Book.create!(osis_code: "Eph", name: "Ephesians", testament: :new, position: 49, chapter_count: 6)
    Verse.create!(translation: kjv, book: eph, chapter: 2, verse_number: 8, text: "For by grace are ye saved through faith")
    FaithTerm.create!(name: "Salvation", short_definition: "God's work of bringing a person into his own life.",
                      position: 0, status: :reviewed, key_references: [ "Ephesians 2:8" ])
    5.times { |i| users(:one).studies.create!(name: "Study #{i}", pane_count: 1) }
  end

  test "a phone gets the word of the day, three studies and the guide's link; Show all reveals the rest" do
    visit new_session_path
    fill_in "email_address", with: users(:one).email_address
    fill_in "password", with: "password"
    click_on "Sign In"
    assert_no_current_path new_session_path
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    visit root_path

    assert_selector ".ft-card .ft-card-term", text: "Salvation"
    assert_no_selector ".ft-card .ft-card-verses", visible: true
    count = all(".hm-study", visible: :all).size
    assert_operator count, :>, 3
    assert_selector ".hm-study", count: 3, visible: true
    assert_no_selector ".ps-guide-grid", visible: true

    click_on "Show all #{count} studies"
    assert_selector ".hm-study", count: count, visible: true
    assert_no_button "Show all"
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "a laptop still sees everything" do
    visit new_session_path
    fill_in "email_address", with: users(:one).email_address
    fill_in "password", with: "password"
    click_on "Sign In"
    assert_no_current_path new_session_path
    visit root_path
    assert_selector ".ft-card .ft-card-verses", visible: true
    assert_no_button "Show all", visible: true
    assert_operator all(".hm-study", visible: true).size, :>, 3
  end
end
