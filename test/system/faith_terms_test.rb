require "application_system_test_case"

# Browser smoke of the Glossary of the Faith: the home slider's word of the day
# leads to the term page and the glossary, whose search filters as you type.
class FaithTermsSystemTest < ApplicationSystemTestCase
  setup do
    kjv = Translation.create!(code: "KJV", name: "King James Version")
    eph = Book.create!(osis_code: "Eph", name: "Ephesians", testament: :new, position: 49, chapter_count: 6)
    Verse.create!(translation: kjv, book: eph, chapter: 2, verse_number: 8, text: "For by grace are ye saved through faith")
    %w[ Grace Covenant Regeneration ].each_with_index do |name, i|
      FaithTerm.create!(name:, short_definition: "#{name} in plain words.", position: i, status: :reviewed,
                        aliases: (name == "Regeneration" ? [ "Born again" ] : []),
                        key_references: [ "Ephesians 2:8" ])
    end
    FaithTerm.create!(name: "Election", short_definition: "A draft nobody may see yet.", position: 9)
  end

  def sign_in
    visit new_session_path
    fill_in "email_address", with: users(:one).email_address
    fill_in "password", with: "password"
    click_on "Sign In"
  end

  test "the home slider leads to the term and the glossary, and the glossary search filters" do
    sign_in
    today = FaithTerm.of_the_day
    within(".hm-glossary") do
      assert_selector ".hm-gl-slide:first-child .hm-gl-term", text: today.name
      first(".hm-gl-slide").click
    end
    assert_selector "h1", text: today.name
    assert_text "For by grace are ye saved"

    visit faith_terms_path
    assert_selector ".ft-item", count: 3
    assert_no_text "Election"

    fill_in "Search the glossary", with: "born again"
    assert_selector ".ft-item", count: 1
    assert_selector ".ft-item", text: "Regeneration"
    assert_no_selector ".ft-letter[data-letter='G']"

    fill_in "Search the glossary", with: "zzz"
    assert_text "No term matches that yet"

    fill_in "Search the glossary", with: ""
    assert_selector ".ft-item", count: 3
  end

  test "from 1024px the side pane stays put while terms open beside it" do
    visit faith_term_path("grace")
    assert_selector "h1", text: "Grace"
    within(".ft-side") do
      assert_selector ".ft-item[aria-current='page']", text: "Grace"
      assert_selector ".ft-item", count: 3
    end
    assert_no_selector ".ft-crumb", visible: true

    # Mark the side pane: a Turbo Frame visit keeps the very same element.
    page.execute_script("document.querySelector('.ft-side').dataset.kept = 'yes'")
    find(".ft-side .ft-item", text: "Covenant").click
    assert_selector ".ft-hero h1", text: "Covenant"
    assert_current_path faith_term_path("covenant")
    assert_selector ".ft-side[data-kept='yes'] .ft-item[aria-current='page']", text: "Covenant"
    assert_selector ".ft-side .ft-item[aria-current='page']", count: 1
    assert_equal "Covenant · Glossary of the Faith · BiblioRata", page.title

    # The search still filters the side pane on a term page.
    fill_in "Search the glossary", with: "born again"
    assert_selector ".ft-side .ft-item", count: 1, text: "Regeneration"

    # Back to the welcome, still in the frame.
    find(".ft-side-title").click
    assert_selector ".ft-welcome h1", text: "The words of the faith"
    assert_selector ".ft-side[data-kept='yes']"
    assert_no_selector ".ft-side .ft-item[aria-current]"
  end

  test "a phone gets the list, then the term alone with a way back to all terms" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    visit faith_terms_path
    assert_selector ".ft-welcome"
    assert_selector ".ft-side .ft-item", count: 3
    assert_no_selector ".ft-today", visible: true
    find(".ft-side .ft-item", text: "Grace").click

    assert_selector ".ft-hero h1", text: "Grace"
    assert_no_selector ".ft-side", visible: true
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth"), "no sideways scroll"
    click_on "All terms"
    assert_selector ".ft-side .ft-item", count: 3, visible: true
    assert_current_path faith_terms_path
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
