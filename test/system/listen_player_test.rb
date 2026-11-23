require "application_system_test_case"

# The Audio Bible's player bar: pause/resume, previous/next verse, speed (with
# 2×), repeat, sleep timer and close — for each way the reader speaks: server
# narration (<audio>), the Android app's phone voice (window.BiblioRataNative)
# and the browser's speechSynthesis. Plus "Play from here" on a tapped verse.
class ListenPlayerTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 412, 915 ], options: { name: :selenium_pixel_player } do |opts|
    opts.add_emulation(device_name: "Pixel 7")
    opts.add_argument("--autoplay-policy=no-user-gesture-required")
    path = begin
      Selenium::WebDriver::SeleniumManager.binary_paths("--browser", "chrome")["browser_path"]
    rescue StandardError
      nil
    end
    opts.binary = path if path.present?
  end

  setup do
    @user = users(:one)
    @user.update!(tour_completed_at: Time.current, guide_dismissed_at: Time.current)
    kjv = Translation.create!(code: "KJV", name: "King James Version")
    jude = Book.create!(osis_code: "Jude", name: "Jude", testament: :new, position: 65, chapter_count: 1)
    (1..6).each { |v| Verse.create!(translation: kjv, book: jude, chapter: 1, verse_number: v, text: "Jude verse #{v} of the one chapter.") }
    @study = @user.studies.create!(name: "Listen", pane_count: 1)
    @study.panes.find_by(position: 0).update!(reference: "Jude 1", translation: kjv)
  end

  test "server narration: pause, verses, speed, repeat, sleep at the end of the chapter, close" do
    open_study
    stub_chapter_audio
    start_listening

    assert_selector ".lp-bar:not([hidden])"
    assert_selector ".lp-status", text: "Playing"
    assert_selector ".lp-label", text: /Jude 1:\d · KJV/
    assert_no_selector ".lp-bar [aria-label='Previous verse'][disabled]"

    # Pause is a real pause; play carries on from the same place.
    find(".lp-play").click
    assert_selector ".lp-status", text: "Paused"
    assert page.evaluate_script("window.__audio.paused")
    at = page.evaluate_script("window.__audio.currentTime")
    find(".lp-play").click
    assert_selector ".lp-status", text: "Playing"
    assert_not page.evaluate_script("window.__audio.paused")
    assert_operator page.evaluate_script("window.__audio.currentTime"), :>=, at

    # Verses start 0.5 s apart in the stub's timings.
    find(".lp-play").click # pause, so time stands still
    assert_selector ".lp-status", text: "Paused"
    6.times { find(".lp-bar [aria-label='Previous verse']").click } # back to the first verse
    assert_selector ".lp-label", text: "Jude 1:1 · KJV"
    assert_in_delta 0.0, page.evaluate_script("window.__audio.currentTime"), 0.05
    find(".lp-bar [aria-label='Next verse']").click
    find(".lp-bar [aria-label='Next verse']").click
    assert_selector ".lp-label", text: "Jude 1:3 · KJV"
    assert_in_delta 1.0, page.evaluate_script("window.__audio.currentTime"), 0.05
    assert_selector ".ps-verse.is-reading[data-verse-num='3']"
    find(".lp-bar [aria-label='Previous verse']").click
    assert_selector ".lp-label", text: "Jude 1:2 · KJV"
    assert_in_delta 0.5, page.evaluate_script("window.__audio.currentTime"), 0.05

    # Speed cycles to 2×, applies at once and is remembered with the sheet's choices.
    3.times { find(".lp-speed").click } # 1 → 1.25 → 1.5 → 2
    assert_selector ".lp-speed", text: "2×"
    assert_equal 2, page.evaluate_script("window.__audio.playbackRate")
    assert_equal 2, page.evaluate_script("JSON.parse(localStorage.getItem('bibliorata:listen')).rate")

    # Repeat: this verse → this chapter → off.
    find(".lp-repeat").click
    assert_selector ".lp-repeat.is-on[aria-label='Repeat this verse']"
    find(".lp-play").click # play
    sleep 1.2 # well past verse 2's half second, even at 2×
    assert_selector ".lp-label", text: "Jude 1:2 · KJV"
    find(".lp-repeat").click
    assert_selector ".lp-repeat[aria-label='Repeat this chapter']"
    find(".lp-repeat").click
    assert_selector ".lp-repeat:not(.is-on)[aria-label='Repeat: off']"

    # Sleep timer: minutes count down on the bar; end of chapter stops there.
    find(".lp-sleep-btn").click
    find(".lp-menu-item[data-sleep='5']").click
    assert_selector ".lp-sleep-left", text: /\A[45]:\d\d\z/
    find(".lp-sleep-btn").click
    find(".lp-menu-item[data-sleep='chapter']").click
    assert_selector ".lp-sleep-btn[aria-label='Sleep timer: end of this chapter']"
    find(".lp-play").click # pause, so the voice doesn't move on by itself
    assert_selector ".lp-status", text: "Paused"
    6.times do
      break if find(".lp-label").text.include?("1:6")
      find(".lp-bar [aria-label='Next verse']").click
      sleep 0.1
    end
    assert_selector ".lp-label", text: "Jude 1:6 · KJV"
    find(".lp-bar [aria-label='Next verse']").click # past the last verse = end of the chapter
    assert_no_selector ".lp-bar", visible: true
    assert page.evaluate_script("window.__audio.paused")

    # The sheet shows the speed picked on the bar.
    find(".ps-pane [data-action~='reader#toggle']").click
    settle_sheet
    assert_selector ".ls-speed [data-rate='2'][aria-checked='true']"
    find(".ls-play").click
    assert_selector ".lp-bar:not([hidden])"
    find(".lp-close").click
    assert_no_selector ".lp-bar", visible: true
    assert_no_selector ".ps-verse.is-reading"
  end

  test "Play from here starts at the tapped verse, and moves there while playing" do
    open_study
    stub_chapter_audio
    find(".ps-verse[data-verse-num='4'] .ps-verse-text").click
    within(".ui-actionbar") { click_on "Play from here" }
    assert_selector ".lp-label", text: /Jude 1:[45] · KJV/
    assert_operator page.evaluate_script("window.__audio.currentTime"), :>=, 1.5
    assert_no_selector ".ui-actionbar", visible: true

    find(".ps-verse[data-verse-num='2'] .ps-verse-text").click
    within(".ui-actionbar") { click_on "Play from here" }
    assert_selector ".lp-label", text: "Jude 1:2 · KJV"
    assert_equal 1, page.evaluate_script("window.__audioAsked.length"), "the playing chapter isn't fetched again"
  end

  test "the Android app's phone voice reads verse by verse: pause, next, repeat" do
    open_study
    page.execute_script(<<~JS)
      localStorage.setItem("bibliorata:voice", "device")
      window.__said = []
      const emit = (d) => window.dispatchEvent(new CustomEvent("native:speech", { detail: d }))
      window.BiblioRataNative = {
        speak(text) { window.__said.push(text); setTimeout(() => emit("start"), 5) },
        stopSpeaking() { setTimeout(() => emit("end"), 5) }
      }
      window.__finishVerse = () => emit("end")
    JS
    start_listening
    assert_selector ".lp-label", text: "Jude 1:1 · KJV"
    assert_equal [ "Jude verse 1 of the one chapter." ], page.evaluate_script("window.__said")
    assert_selector ".lp-speed[disabled]" # this voice reads at one speed

    sleep 0.1
    page.execute_script("window.__finishVerse()")
    assert_selector ".lp-label", text: "Jude 1:2 · KJV"

    find(".lp-play").click
    assert_selector ".lp-status", text: "Paused"
    find(".lp-bar [aria-label='Next verse']").click
    assert_selector ".lp-label", text: "Jude 1:3 · KJV"
    find(".lp-play").click
    assert_selector ".lp-status", text: "Playing"
    assert_equal "Jude verse 3 of the one chapter.", page.evaluate_script("window.__said.at(-1)")

    find(".lp-repeat").click # this verse
    sleep 0.1
    page.execute_script("window.__finishVerse()")
    assert_selector ".lp-label", text: "Jude 1:3 · KJV"
    assert_equal "Jude verse 3 of the one chapter.", page.evaluate_script("window.__said.at(-1)")

    find(".lp-close").click
    assert_no_selector ".lp-bar", visible: true
  end

  test "the browser's own voice reads verse by verse and restarts a verse at a new speed" do
    open_study
    page.execute_script(<<~JS)
      localStorage.setItem("bibliorata:voice", "device")
      window.__spoken = []
      class FakeUtterance { constructor(text) { this.text = text } }
      const synth = {
        speaking: false, pending: false, current: null,
        speak(u) { this.current = u; this.speaking = true; window.__spoken.push({ text: u.text, rate: u.rate }) },
        cancel() { const u = this.current; this.current = null; this.speaking = false; if (u) setTimeout(() => u.onerror?.({ error: "interrupted" }), 0) },
        finish() { const u = this.current; this.current = null; this.speaking = false; u?.onend?.() }
      }
      Object.defineProperty(window, "speechSynthesis", { value: synth, configurable: true })
      window.SpeechSynthesisUtterance = FakeUtterance
    JS
    find(".ps-verse[data-verse-num='5'] .ps-verse-text").click
    within(".ui-actionbar") { click_on "Play from here" }
    assert_selector ".lp-label", text: "Jude 1:5 · KJV"
    assert_equal "Jude verse 5 of the one chapter.", page.evaluate_script("window.__spoken.at(-1).text")

    page.execute_script("window.speechSynthesis.finish()")
    assert_selector ".lp-label", text: "Jude 1:6 · KJV"

    find(".lp-speed").click # 1 → 1.25: say this verse again, faster
    assert_selector ".lp-speed", text: "1.25×"
    sleep 0.2
    spoken = page.evaluate_script("window.__spoken.at(-1)")
    assert_equal "Jude verse 6 of the one chapter.", spoken["text"]
    assert_in_delta 0.92 * 1.25, spoken["rate"], 0.001

    find(".lp-bar [aria-label='Previous verse']").click
    assert_selector ".lp-label", text: "Jude 1:5 · KJV"
    find(".lp-play").click
    assert_selector ".lp-status", text: "Paused"
    assert_not page.evaluate_script("window.speechSynthesis.speaking")
    find(".lp-close").click
    assert_no_selector ".lp-bar", visible: true
  end

  private

  def settle_sheet = sleep(0.4)

  def open_study
    visit new_session_path
    fill_in "email_address", with: @user.email_address
    fill_in "password", with: "password"
    click_on "Sign In"
    assert_no_current_path new_session_path
    visit study_path(@study)
    wait_for_reader_js
  end

  def start_listening
    find(".ps-pane [data-action~='reader#toggle']").click
    assert_selector ".ui-listen-sheet.is-open"
    settle_sheet
    find(".ls-play").click
  end

  # As in compare_listen_test: "ready" with 30 s of silence made in the page,
  # each verse 0.5 s after the one before.
  def stub_chapter_audio
    page.execute_script(<<~JS)
      const rate = 8000, seconds = 30, bytes = rate * seconds
      const buf = new ArrayBuffer(44 + bytes), v = new DataView(buf)
      const put = (o, s) => [...s].forEach((c, i) => v.setUint8(o + i, c.charCodeAt(0)))
      put(0, "RIFF"); v.setUint32(4, 36 + bytes, true); put(8, "WAVEfmt ")
      v.setUint32(16, 16, true); v.setUint16(20, 1, true); v.setUint16(22, 1, true)
      v.setUint32(24, rate, true); v.setUint32(28, rate, true); v.setUint16(32, 1, true); v.setUint16(34, 8, true)
      put(36, "data"); v.setUint32(40, bytes, true)
      for (let i = 0; i < bytes; i++) v.setUint8(44 + i, 128)
      const url = URL.createObjectURL(new Blob([buf], { type: "audio/wav" }))
      const timings = {}; for (let n = 1; n <= 40; n++) timings[n] = (n - 1) * 0.5
      window.__audioAsked = []
      const realFetch = window.fetch.bind(window)
      window.fetch = (input, init) => {
        const href = String(input?.url || input)
        if (!href.startsWith("/audio/chapter")) return realFetch(input, init)
        const q = new URL(href, location.origin).searchParams
        window.__audioAsked.push(`/audio/chapter?osis=${q.get("osis")}&chapter=${q.get("chapter")}`)
        const body = { ok: true, status: "ready", url, timings, duration: seconds, book: "Jude",
                       chapter: Number(q.get("chapter")), translation: q.get("translation"), title: "Test", voice: "human" }
        return Promise.resolve(new Response(JSON.stringify(body), { headers: { "Content-Type": "application/json" } }))
      }
      const play = HTMLMediaElement.prototype.play
      HTMLMediaElement.prototype.play = function () { window.__audio = this; this.muted = true; return play.call(this) }
    JS
  end
end
