require "application_system_test_case"

# Looks + live controls on the projector (screen_look / screen_live
# controllers): pick a look, Clear / Logo / Black, a countdown, an alert, the
# crossfade, and Back across songs and queue items. Two windows: the operator
# console and the ?output=1 projector, synced over the BroadcastChannel.
class SlideLooksTest < ApplicationSystemTestCase
  SHOTS = ENV["LOOKS_SCREENSHOTS"].presence

  SONG = <<~SONG.strip
    [Verse 1]
    Amazing grace! How sweet the sound
    That saved a wretch like me!

    [Verse 2]
    'Twas grace that taught my heart to fear,
    And grace my fears relieved;
  SONG

  setup do
    kjv = Translation.create!(code: "KJV", name: "King James Version")
    john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    {
      14 => "And as Moses lifted up the serpent in the wilderness, even so must the Son of man be lifted up:",
      15 => "That whosoever believeth in him should not perish, but have eternal life.",
      16 => "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.",
      17 => "For God sent not his Son into the world to condemn the world; but that the world through him might be saved."
    }.each { |num, text| Verse.create!(translation: kjv, book: john, chapter: 3, verse_number: num, text: text) }
    FileUtils.mkdir_p(SHOTS) if SHOTS
  end

  test "pick a look, then Clear, Logo, Black, a countdown and an alert reach the projector" do
    start_preaching("John 3:16")
    projector = open_window("output")

    # Looks: the picker, on both screens, remembered for the study.
    find("[data-action~='presentation#toggleScreenPanel']").click
    assert_selector ".ps-looks .ps-look-tile", minimum: 12
    find(".ps-look-tile[data-look-id='royal']").click
    assert_selector ".ps-look-tile.is-on[data-look-id='royal']"
    fill_in "Church name", with: "Grace Chapel Ikeja"
    shot "looks-picker"
    find(".ps-looks .done").click
    assert_selector ".ps-root[data-look='royal'][data-look-ref='bottom']"
    within_window(projector) do
      assert_selector ".ps-root.is-output[data-look='royal']"
      assert_selector ".ps-pane.is-presented .ps-verse.is-preach-current[data-verse-num='16']"
      shot "projector-royal"
    end

    # Clear: words hidden, background kept — until the next slide goes up.
    find(".ps-live-btn.is-clear").click
    assert_selector "[data-screen-state][data-state='clear']", text: /cleared/i
    within_window(projector) do
      assert_selector ".ps-root.screen-clear"
      assert_no_selector ".ps-pane.is-presented .ps-verse.is-preach-current", visible: true
      assert_selector ".ps-look-bg", visible: true
    end
    send_keys :arrow_right
    assert_selector "[data-preach-counter]", text: /verse 17/i
    within_window(projector) do
      assert_no_selector ".ps-root.screen-clear"
      assert_selector ".ps-pane.is-presented .ps-verse.is-preach-current[data-verse-num='17']", visible: true
    end
    assert_selector "[data-screen-state]", visible: :hidden

    # Logo (O): the church name on the look's background; again to go back.
    send_keys "o"
    assert_selector "[data-screen-state][data-state='logo']", text: /logo on screen/i
    within_window(projector) do
      assert_selector ".ps-screen-logo .logo-name", text: /grace chapel ikeja/i, visible: true
      assert_no_selector ".ps-pane.is-presented .ps-verse.is-preach-current", visible: true
      shot "projector-logo"
    end

    # Black (.) takes over: fully black, logo off.
    send_keys "."
    assert_selector "[data-screen-state][data-state='black']", text: /black/i
    assert_selector ".ps-live-btn.is-black.is-on"
    assert_no_selector ".ps-live-btn.is-logo.is-on"
    within_window(projector) do
      assert_selector ".ps-root.is-blank .ps-preach-hold", visible: true
      assert_no_selector ".ps-root.screen-logo"
    end
    send_keys "."
    within_window(projector) { assert_no_selector ".ps-root.is-blank" }

    # Countdown (T): a few seconds, then the logo comes up by itself.
    send_keys "t"
    assert_selector "[data-screen-live-target='timerPanel']", visible: true
    assert_equal "Service starts in", find("[data-screen-live-target='heading']").value
    page.execute_script("document.querySelector(\"[data-screen-live-target='minutes']\").value = '0.05'") # 3 s
    click_on "Start countdown"
    assert_selector "[data-screen-state][data-state='countdown']", text: /countdown 00:0\d/i
    within_window(projector) do
      assert_selector ".ps-screen-countdown .cd-head", text: /service starts in/i, visible: true
      assert_selector ".ps-screen-countdown .cd-digits", text: /\A00:0\d\z/, visible: true
      shot "projector-countdown"
    end
    assert_selector "[data-screen-state][data-state='logo']", wait: 8
    within_window(projector) { assert_selector ".ps-screen-logo", visible: true }
    send_keys "o"
    assert_no_selector ".ps-live-btn.is-logo.is-on"

    # Alert (A): a lower-third over whatever is live — projector and stage.
    stage = open_window("stage")
    send_keys "a"
    find("[data-screen-live-target='alertText']").fill_in(with: "Parent of child 12, please come to the nursery")
    find("[data-screen-live-target='alertSeconds']").select("when I dismiss it")
    click_on "Show alert"
    assert_selector "[data-screen-state] .st-alert", text: /child 12/
    within_window(projector) do
      assert_selector ".ps-screen-alert", text: "Parent of child 12, please come to the nursery", visible: true
      assert_selector ".ps-pane.is-presented .ps-verse.is-preach-current", visible: true
      shot "projector-alert"
    end
    within_window(stage) { assert_selector ".ps-screen-alert", text: /child 12/, visible: true }
    find("[data-screen-state] .st-dismiss").click
    within_window(projector) { assert_no_selector ".ps-screen-alert", visible: true }
    within_window(stage) { assert_no_selector ".ps-screen-alert", visible: true }

    # The look was kept for this study: a fresh projector comes up in it.
    within_window(projector) do
      visit current_url
      assert_selector ".ps-root.is-output[data-look='royal']"
    end
  end

  test "slides crossfade on the projector; Cut switches it off" do
    start_preaching("John 3:16")
    projector = open_window("output")
    within_window(projector) do
      page.execute_script(<<~JS)
        window.__fades = 0
        const start = document.startViewTransition?.bind(document)
        if (start) document.startViewTransition = (cb) => { window.__fades++; return start(cb) }
      JS
    end
    send_keys :arrow_right
    within_window(projector) do
      assert_selector ".ps-verse.is-preach-current[data-verse-num='17']"
      assert_operator page.evaluate_script("window.__fades"), :>=, 1, "Next crossfades on the projector"
    end

    find("[data-action~='presentation#toggleScreenPanel']").click
    find(".ps-looks [data-transition='cut']").click
    find(".ps-looks .done").click
    within_window(projector) do
      assert_selector ".ps-root[data-slide-transition='cut']"
      page.execute_script("window.__fades = 0")
    end
    send_keys :arrow_left
    within_window(projector) do
      assert_selector ".ps-verse.is-preach-current[data-verse-num='16']"
      assert_equal 0, page.evaluate_script("window.__fades"), "Cut never fades"
    end
  end

  test "Back returns from a song to the scripture, and from a queue scripture to the song" do
    start_preaching("John 3:16")
    present_song
    assert_selector ".ps-root.is-slide [data-preach-slide] .slide-stanza", text: /Amazing grace/
    send_keys :arrow_right
    assert_selector "[data-preach-slide] .slide-stanza", text: /Twas grace/

    send_keys "b"
    assert_no_selector ".ps-root.is-slide"
    assert_selector "[data-preach-counter]", text: /verse 16/i

    present_song
    send_keys :arrow_right
    assert_selector "[data-preach-slide] .slide-stanza", text: /Twas grace/
    page.execute_script("window.dispatchEvent(new CustomEvent('setlist:present', { detail: { kind: 'scripture', reference: 'John 3:14' } }))")
    assert_selector "[data-preach-counter]", text: /verse 14/i
    find("[data-preach-back]").click
    assert_selector "[data-preach-slide] .slide-stanza", text: /Twas grace/, wait: 5
  end

  private

  def start_preaching(reference)
    visit root_path
    page.execute_script("localStorage.setItem('scriptorium.tourDone', '1')")
    fill_in "reference", with: reference
    click_on "Read"
    assert_selector ".ps-pane .ps-verse"
    find(".ui-appbar button[data-action~='presentation#start']").click
    assert_selector ".ps-root.is-preaching[data-look]"
    assert_selector "[data-preach-counter]", text: /of 17/i # the whole chapter is in
    @operator = current_window
  end

  def open_window(kind)
    path = URI(current_url).path
    win = open_new_window
    within_window(win) do
      visit "#{path}?#{kind}=1&pane=0"
      assert_selector ".ps-root.is-output.is-preaching"
    end
    win
  end

  def present_song
    page.execute_script(<<~JS, SONG)
      window.dispatchEvent(new CustomEvent("setlist:present", { detail: { kind: "slide", title: "Amazing Grace", body: arguments[0] } }))
    JS
  end

  def send_keys(*keys)
    find("body").send_keys(*keys)
  end

  def shot(name)
    page.save_screenshot(File.join(SHOTS, "#{name}.png")) if SHOTS
  end
end
