require "application_system_test_case"

# The home on a phone: greeting and one search box, the verse of the day over
# a painting (reflection folded), Continue reading, today's plan, quick
# actions, the glossary slider, three studies then "Show all". Laptops get
# two columns at the top and the slider three across.
class HomePhoneTest < ApplicationSystemTestCase
  APP_UA = "BiblioRata/1.0.4; NativeBridge; Hotwire Native Android; Turbo Native Android; " \
           "Mozilla/5.0 (Linux; Android 16; wv) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Mobile Safari/537.36"

  setup do
    kjv = Translation.create!(code: "KJV", name: "King James Version")
    eph = Book.create!(osis_code: "Eph", name: "Ephesians", testament: :new, position: 49, chapter_count: 6)
    Verse.create!(translation: kjv, book: eph, chapter: 2, verse_number: 8, text: "For by grace are ye saved through faith")
    DailyWord::REFERENCES.first(2).each_with_index do |ref, i|
      parsed = ReferenceParser.call(ref)
      book = Book.find_by_osis(parsed.osis) ||
             Book.create!(osis_code: parsed.osis, name: parsed.book_name, testament: :new, position: 100 + i, chapter_count: 150)
      Verse.create!(translation: kjv, book:, chapter: parsed.chapter, verse_number: parsed.verse_start, text: "Seeded #{ref}")
    end
    @word = DailyWord.ensure_for(DailyWord.today_date)
    @word.update!(reflection: "Rest in this today.", prayer: "Lord, keep us. Amen.", composed_at: Time.current)
    FaithTerm.create!(name: "Salvation", short_definition: "God's work of bringing a person into his own life.",
                      position: 0, status: :reviewed, key_references: [ "Ephesians 2:8" ])
    FaithTerm.create!(name: "Grace", short_definition: "God's enabling power that brings salvation.",
                      position: 1, status: :reviewed, key_references: [ "Ephesians 2:8" ])
    FaithTerm.create!(name: "Election", short_definition: "A draft nobody may see yet.", position: 2)
    5.times { |i| users(:one).studies.create!(name: "Study #{i}", pane_count: 1) }
  end

  test "a phone gets the verse, the slider, three studies and Show all; the prayer unfolds" do
    sign_in
    phone
    visit root_path

    assert_selector ".hm-hello h1", text: /Good (morning|afternoon|evening)/
    within(".hm-verse") do
      assert_selector ".hm-verse-text", text: @word.verse_text
      assert_no_selector ".hm-reflect-prayer", visible: true
      find(".hm-reflect summary").click
      assert_selector ".hm-reflect-prayer", text: "Lord, keep us. Amen.", visible: true
    end
    # The phone gets the small picture.
    src = page.evaluate_script("document.querySelector('.hm-verse-art img').currentSrc")
    assert_match(/-800[-.]/, src)

    assert_selector ".hm-actions .hm-action", count: 4, visible: true
    assert_selector ".hm-glossary .hm-gl-slide", count: 3, visible: true
    today = FaithTerm.of_the_day
    within(first(".hm-gl-slide")) do
      assert_text "WORD OF THE DAY"
      assert_selector ".hm-gl-term", text: today.name
    end
    assert_no_text "Election"
    no_overflow = page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
    assert no_overflow, "the slider scrolls inside itself, not the page"

    count = all(".hm-study", visible: :all).size
    assert_operator count, :>, 3
    assert_selector ".hm-study", count: 3, visible: true
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

  test "a reference in the search box opens the reader there" do
    sign_in
    find(".hm-search-input").send_keys("Eph 2:8", :enter)
    assert_selector ".ps-verse.is-focus[data-verse-num='8']", text: "For by grace", wait: 5
  end

  test "Read the chapter opens the reader at today's verse" do
    sign_in
    within(".hm-verse") { click_on "Read the chapter" }
    assert_selector ".ps-verse.is-focus", text: "Seeded #{DailyWord::REFERENCES.first}", wait: 5
  end

  test "a laptop gets two columns at the top and the slider three across" do
    sign_in
    hero = find(".hm-verse").rect
    side = find(".hm-side").rect
    assert_operator side.x, :>, hero.x + hero.width - 1, "Continue / plan sit beside the verse"
    slides = all(".hm-gl-slide", visible: true).first(3).map { |s| s.rect.y.round }
    assert_equal 1, slides.uniq.size
    assert_no_button "Show all", visible: true
    assert_operator all(".hm-study", visible: true).size, :>, 3
  end

  test "inside the app a guest's Home tab is the Bible home with an invitation" do
    page.driver.browser.execute_cdp("Network.setUserAgentOverride", userAgent: APP_UA)
    phone
    visit root_path
    assert_selector ".hm-root.is-guest .hm-verse"
    assert_selector ".hm-resume", text: /Start reading/i
    assert_selector ".hm-join", text: /Create a free account to keep notes, highlights and reading plans/
    assert_no_selector ".ui-tabbar", visible: true # the app has its own
    assert_no_selector ".ps-landing"
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.driver.browser.execute_cdp("Network.setUserAgentOverride", userAgent: "")
  end

  private

  def phone
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 2, mobile: true)
  end

  def sign_in
    visit new_session_path
    fill_in "email_address", with: users(:one).email_address
    fill_in "password", with: "password"
    click_on "Sign In"
    assert_selector ".hm-hello"
  end
end
