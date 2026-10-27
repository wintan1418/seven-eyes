require "application_system_test_case"

# The data-loss paths in the workspace, driven in a real browser:
#   • highlighting KJV words that are split into Strong's spans
#   • a highlight note closed with Esc
#   • notes typed just before a translation switch
class StudySavingTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @user.update!(tour_completed_at: Time.current) # the first-run tour would sit over the verses
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @web = Translation.create!(code: "WEB", name: "World English Bible")
    @jer = Book.create!(osis_code: "Jer", name: "Jeremiah", testament: :old, position: 24, chapter_count: 52)
    tokens = [ { "w" => "Behold", "s" => "H2005" }, { "w" => ", I am against thee, O destroying " },
               { "w" => "mountain", "s" => "H2022" }, { "w" => ", saith the LORD." } ]
    @verse = Verse.create!(translation: @kjv, book: @jer, chapter: 51, verse_number: 25, tokens: tokens,
                           text: "Behold, I am against thee, O destroying mountain, saith the LORD.")
    Verse.create!(translation: @web, book: @jer, chapter: 51, verse_number: 25,
                  text: "Behold, I am against you, destroying mountain, says Yahweh.")
    @study = @user.studies.create!(name: "Jeremiah", pane_count: 1)
    @pane = @study.panes.first
    @pane.update!(reference: "Jeremiah 51:25", translation: @kjv)
  end

  test "highlighting across Strong's word spans shows at once and its note saves on Esc" do
    sign_in
    visit study_path(@study)
    text = ".ps-verse[data-verse-num='25'] .ps-verse-text"
    assert_selector "#{text} .ps-word", minimum: 2

    # Select from the middle of "Behold" (a Strong's span) to the middle of
    # "mountain" (another one) — the range crosses element boundaries.
    page.execute_script(<<~JS)
      const words = document.querySelectorAll(#{text.to_json} + " .ps-word");
      const r = document.createRange();
      r.setStart(words[0].firstChild, 2);
      r.setEnd(words[1].firstChild, 4);
      const sel = getSelection(); sel.removeAllRanges(); sel.addRange(r);
      document.querySelector(#{text.to_json}).dispatchEvent(new MouseEvent("mouseup", { bubbles: true }));
    JS
    find(".ps-hl-popover button[aria-label='Highlight ochre']").click

    assert_selector "#{text} .hl-ochre", minimum: 2, wait: 3
    highlight = @user.highlights.sole
    assert_equal [ 2, 44 ], [ highlight.char_start, highlight.char_end ]
    assert_equal "hold, I am against thee, O destroying moun",
                 @verse.text[highlight.char_start...highlight.char_end]
    assert_equal "hold, I am against thee, O destroying moun",
                 page.evaluate_script("[...document.querySelectorAll(#{"#{text} .hl-ochre".to_json})].map(s => s.textContent).join('')")

    # The note editor opened straight away; Esc closes it and saves.
    find(".ps-hl-edit .ps-hl-note").fill_in(with: "Babylon, the destroying mountain")
    find(".ps-hl-edit .ps-hl-note").send_keys(:escape)
    assert_no_selector ".ps-hl-edit", wait: 3
    assert_equal "Babylon, the destroying mountain", highlight.reload.note
  end

  test "notes typed just before a translation switch are kept" do
    sign_in
    visit study_path(@study)
    wait_for_reader_js
    find(".ps-pane-tool[title='Notes']").click
    find(".ps-notes-area").fill_in(with: "Written a heartbeat before switching")
    # Switch inside the 700ms debounce window: the frame request must wait for
    # the notes to land, and the re-rendered pane must show them.
    find(".ui-appbar [data-sheets-id-param='translation']").click
    find(".ui-translation-sheet .ui-option", text: "WEB").click
    assert_selector ".ps-verse-text", text: /says Yahweh/, wait: 5
    assert_equal "Written a heartbeat before switching", @pane.reload.notes
    assert_equal "Written a heartbeat before switching", find(".ps-notes-area", visible: :all).value
  end

  test "Cmd/Ctrl+S saves notes immediately and says so" do
    sign_in
    visit study_path(@study)
    wait_for_reader_js
    find(".ps-pane-tool[title='Notes']").click
    area = find(".ps-notes-area")
    area.fill_in(with: "Saved by the shortcut")
    area.send_keys([ :control, "s" ])
    # The toast animates in from off-screen, so read its text rather than
    # relying on Selenium's visibility check.
    assert_selector ".ps-toast.js-flash", text: "Saved", visible: :all, wait: 3
    assert_equal "Saved by the shortcut", @pane.reload.notes
  end

  test "a guest pressing Cmd/Ctrl+S gets the create-an-account gate, not a false 'Saved'" do
    visit root_path
    fill_in "reference", with: "Jeremiah 51:25"
    click_on "Read"
    assert_selector ".ps-verse"
    find("body").send_keys([ :control, "s" ])
    assert_selector ".ps-auth-modal.is-open", wait: 3
    assert_no_selector ".ps-toast.js-flash", text: "✓ Saved", visible: :all
  end

  private

  def sign_in
    visit new_session_path
    fill_in "email_address", with: @user.email_address
    fill_in "password", with: "password"
    click_on "Sign In"
    assert_no_current_path new_session_path
  end
end
