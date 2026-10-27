require "application_system_test_case"

# Tap verses → the action bar: highlight, note, compare, copy, share and the
# overflow tools. Preach mode must ignore taps entirely.
class VerseActionsTest < ApplicationSystemTestCase
  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @bsb = Translation.create!(code: "BSB", name: "Berean Standard Bible")
    john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    {
      15 => "That whosoever believeth in him should not perish",
      16 => "For God so loved the world",
      17 => "For God sent not his Son into the world to condemn the world"
    }.each do |n, text|
      Verse.create!(translation: @kjv, book: john, chapter: 3, verse_number: n, text:)
      Verse.create!(translation: @bsb, book: john, chapter: 3, verse_number: n, text: "BSB #{n}")
    end
    @user = users(:one)
    @user.update!(tour_completed_at: Time.current)
  end

  test "tapping two verses names them in the bar; copy puts text and reference on the clipboard" do
    open_john3
    tap_verse(16)
    tap_verse(17)
    assert_selector ".ui-actionbar .ui-actionbar-label", text: "John 3:16–17"
    assert_selector ".ps-verse.is-selected", count: 2

    page.driver.browser.execute_cdp("Browser.grantPermissions",
      permissions: %w[clipboardReadWrite clipboardSanitizedWrite], origin: page.server_url)
    find(".ui-actionbar button", text: "Copy").click
    assert_selector ".ps-toast.js-flash", text: "Copied", visible: :all
    clip = page.evaluate_async_script("navigator.clipboard.readText().then(arguments[0])")
    assert_includes clip, "16 For God so loved the world 17 For God sent not"
    assert_includes clip, "— John 3:16–17 KJV"
    assert_no_selector ".ui-actionbar", visible: true

    tap_verse(16)
    tap_verse(16) # tapping again lets go
    assert_no_selector ".ps-verse.is-selected"
    assert_no_selector ".ui-actionbar", visible: true
  end

  test "a guest highlighting gets the create-an-account gate" do
    open_john3
    tap_verse(16)
    find(".ui-actionbar button[aria-label='Highlight ochre']").click
    assert_selector ".ps-auth-modal.is-open", wait: 3
  end

  test "signed in: highlight a whole verse, edit it from the highlight; Note links the verse in the notes" do
    sign_in
    study = @user.studies.create!(name: "John")
    study.panes.first.update!(reference: "John 3", translation: @kjv)
    visit study_path(study)
    tap_verse(16)
    find(".ui-actionbar button[aria-label='Highlight ochre']").click
    assert_selector ".ps-verse[data-verse-num='16'] .hl-ochre", text: "For God so loved the world"
    assert_equal [ 0, 26 ], [ @user.highlights.sole.char_start, @user.highlights.sole.char_end ]

    # Tapping a highlight opens its own editor (colour, note, delete).
    find(".ps-verse[data-verse-num='16'] .hl-ochre").click
    assert_selector ".ps-hl-edit"
    find(".ps-hl-edit .ps-hl-del").click
    assert_no_selector ".ps-verse[data-verse-num='16'] .hl-ochre"
    assert_equal 0, @user.highlights.count

    tap_verse(17)
    find(".ui-actionbar button", text: "Note").click
    assert_selector ".ps-notes-form.is-open"
    assert_equal "[[John 3:17]] ", find(".ps-notes-area").value
  end

  test "overflow: cross-references open the panel; Compare adds a pane" do
    open_john3
    tap_verse(16)
    find(".ui-actionbar button", text: "More").click
    find(".ui-popmenu button", text: "Cross-references").click
    assert_selector ".ps-xref-host.is-open"
    find(".ps-xref-host.is-open .close").click

    assert_selector ".ps-verse.is-selected" # still selected after the panel closes
    find(".ui-actionbar button", text: "Compare").click
    assert_selector ".ps-workspace .ps-pane", count: 2
    assert_selector ".ps-pane .ps-verse-text", text: "BSB 16"
  end

  test "tapping a verse while preaching does nothing" do
    open_john3
    find(".ui-appbar button[data-action~='presentation#start']").click
    assert_selector ".ps-root.is-preaching"
    page.execute_script("document.querySelector(\".ps-pane .ps-verse[data-verse-num='16'] .ps-verse-text\").click()")
    assert_no_selector ".ps-verse.is-selected"
    assert_no_selector ".ui-actionbar", visible: true
  end

  private

  def open_john3
    visit root_path
    page.execute_script("localStorage.setItem('scriptorium.tourDone', '1')")
    fill_in "reference", with: "John 3"
    click_on "Read"
    assert_selector ".ps-verse", minimum: 3
  end

  def tap_verse(n)
    wait_for_reader_js
    find(".ps-pane .ps-verse[data-verse-num='#{n}'] .ps-verse-text").click
  end

  def sign_in
    visit new_session_path
    fill_in "email_address", with: @user.email_address
    fill_in "password", with: "password"
    click_on "Sign In"
    assert_no_current_path new_session_path
  end
end
