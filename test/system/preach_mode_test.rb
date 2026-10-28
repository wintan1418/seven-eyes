require "application_system_test_case"

# Preach mode is driven live during a service, so the regressions that matter
# most are the ones a single stray key could cause in front of a congregation.
class PreachModeTest < ApplicationSystemTestCase
  setup do
    kjv = Translation.create!(code: "KJV", name: "King James Version")
    john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    {
      3 => { 14 => "And as Moses lifted up the serpent in the wilderness",
             15 => "That whosoever believeth in him should not perish",
             16 => "For God so loved the world, that he gave his only begotten Son",
             17 => "For God sent not his Son into the world to condemn the world",
             18 => "He that believeth on him is not condemned" },
      4 => { 1 => "When therefore the Lord knew how the Pharisees had heard",
             2 => "Though Jesus himself baptized not, but his disciples",
             3 => "He left Judaea, and departed again into Galilee" }
    }.each do |chapter, verses|
      verses.each do |num, text|
        Verse.create!(translation: kjv, book: john, chapter: chapter, verse_number: num, text: text)
      end
    end
  end

  test "a single-verse pane opens the whole chapter in preach mode, landing on that verse" do
    start_preaching("John 3:16")
    assert_selector "[data-preach-counter]", text: /verse 16/i
    assert_selector "[data-preach-counter]", text: /of 18/i

    send_keys :arrow_right
    assert_selector "[data-preach-counter]", text: /verse 17/i
    assert_selector ".ps-pane.is-presented .ps-verse.is-preach-current[data-verse-num='17']"
  end

  test "Esc in the Go box closes the box and stays in preach mode" do
    start_preaching("John 3")
    send_keys "g"
    assert_selector ".ps-preach-jump input:focus"
    find(".ps-preach-jump input").send_keys(:escape)
    assert_no_selector ".ps-preach-jump input", visible: true
    assert_selector ".ps-root.is-preaching"
  end

  test "modifier chords never drive the projector; group keys match the bar" do
    start_preaching("John 3")
    send_keys [ :control, "0" ]
    send_keys [ :control, "p" ]
    assert_no_selector ".ps-root.is-blank"
    assert_no_selector ".ps-root.is-parallel"

    send_keys "4" # only 1–3 exist on the bar
    assert_selector ".ps-preach-group button.is-on[data-preach-group='1']"
    send_keys "2"
    assert_selector ".ps-preach-group button.is-on[data-preach-group='2']"

    send_keys "0"
    assert_selector ".ps-root.is-blank"
  end

  test "while live, leaving preach takes two Esc presses and never ends the session" do
    start_preaching("John 3")
    find(".ps-golive").click
    assert_selector ".ps-root.is-live-session"
    click_on "Continue preaching"

    send_keys :escape
    assert_selector ".ps-preach-toast", text: /press esc again/i
    assert_selector ".ps-root.is-preaching"

    send_keys :escape
    assert_no_selector ".ps-root.is-preaching"
    assert_equal 1, LiveSession.active.count, "leaving preach must not end the live session"
    assert_selector ".ps-root.is-live-session"
  end

  test "emphasis does not leak into the next passage" do
    start_preaching("John 3")
    find("[data-preach-emph]").click
    first(".ps-pane.is-presented .ps-verse.is-preach-current .ps-eword").click
    assert_selector ".ps-eword.is-emph"
    find("[data-preach-emph]").click # disarm

    send_keys "g"
    find(".ps-preach-jump input").send_keys("John 4:1", :enter)
    assert_selector "[data-preach-counter]", text: /of 3/i
    assert_no_selector ".ps-eword.is-emph"
    assert_equal({}, page.evaluate_script(<<~JS))
      window.Stimulus.getControllerForElementAndIdentifier(document.querySelector(".ps-root"), "presentation")._emphasis
    JS
  end

  test "the projector window never shows onboarding and is display-only" do
    visit root_path
    fill_in "reference", with: "John 3"
    click_on "Read"
    assert_selector ".ps-pane .ps-verse"
    page.execute_script("localStorage.removeItem('scriptorium.tourDone')") # a fresh guest would get the tour
    visit "#{current_path}?output=1&pane=0"
    assert_selector ".ps-root.is-output.is-preaching"
    sleep 1 # the tour starts 600ms after connect when it is attached
    assert_no_selector ".ps-tour"
    assert_no_selector ".ps-preach-bar", visible: true
  end

  test "focus mode from the More sheet, then the Preach Mode pill" do
    visit root_path
    page.execute_script("localStorage.setItem('scriptorium.tourDone', '1')")
    fill_in "reference", with: "John 3:16"
    click_on "Read"
    assert_selector ".ps-pane .ps-verse"
    find(".ui-appbar [data-sheets-id-param='more']").click
    find(".ui-more-sheet button[title='Focus this pane (presentation mode)']").click
    assert_selector ".ps-root.is-presenting .ps-pane.is-presented"
    assert_no_selector ".ui-appbar", visible: true
    find(".ps-preach-enter").click
    assert_selector ".ps-root.is-preaching"
    assert_selector "[data-preach-counter]", text: /verse 16/i
  end

  private

  def start_preaching(reference)
    visit root_path
    page.execute_script("localStorage.setItem('scriptorium.tourDone', '1')")
    fill_in "reference", with: reference
    click_on "Read"
    assert_selector ".ps-pane .ps-verse"
    # The app bar's Preach button goes straight from reading to preaching.
    find(".ui-appbar button[data-action~='presentation#start']").click
    assert_selector ".ps-root.is-preaching"
  end

  def send_keys(*keys)
    find("body").send_keys(*keys)
  end
end
