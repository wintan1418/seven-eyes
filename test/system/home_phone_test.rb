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
    FaithTerm.create!(name: "Grace", short_definition: "God's enabling power that brings salvation.",
                      position: 1, status: :reviewed, key_references: [ "Ephesians 2:8" ])
    FaithTerm.create!(name: "Election", short_definition: "A draft nobody may see yet.", position: 2)
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

    # The glossary slider replaces the single card: today's word first, then
    # the rest, then "See all"; drafts stay out.
    assert_no_selector ".ft-card", visible: true
    assert_selector ".hm-glossary .hm-gl-slide", count: 3, visible: true
    today = FaithTerm.of_the_day
    within(first(".hm-gl-slide")) do
      assert_text "WORD OF THE DAY"
      assert_selector ".hm-gl-term", text: today.name
    end
    assert_no_text "Election"
    assert_selector ".hm-glossary-track", visible: true
    no_overflow = page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
    assert no_overflow, "the slider scrolls inside itself, not the page"
    count = all(".hm-study", visible: :all).size
    assert_operator count, :>, 3
    assert_selector ".hm-study", count: 3, visible: true
    assert_no_selector ".ps-guide-grid", visible: true

    click_on "Show all #{count} studies"
    assert_selector ".hm-study", count: count, visible: true
    assert_no_button "Show all"

    # A dot moves the slider; tapping a card opens that word.
    other = (FaithTerm.reviewed.in_order.to_a - [ today ]).first
    all(".hm-gl-dot")[1].click
    assert_selector ".hm-gl-dot.is-on[data-index='1']", wait: 5
    find(".hm-gl-slide", text: other.name).click
    assert_current_path faith_term_path(other)
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
    assert_no_selector ".hm-glossary", visible: true
    assert_no_button "Show all", visible: true
    assert_operator all(".hm-study", visible: true).size, :>, 3
  end
end
