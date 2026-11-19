require "application_system_test_case"

# Trello: in Parallel (Compare) mode on a phone there was no way to listen —
# the per-pane Listen buttons are hidden there. Compare's bar now has a Listen
# pill; the Listen sheet asks which passage to hear (top / left by default),
# and only that pane lights up and follows the voice.
class CompareListenTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 412, 915 ], options: { name: :selenium_pixel_compare } do |opts|
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
    isaiah = Book.create!(osis_code: "Isa", name: "Isaiah", testament: :old, position: 23, chapter_count: 66)
    hebrews = Book.create!(osis_code: "Heb", name: "Hebrews", testament: :new, position: 58, chapter_count: 13)
    (1..21).each { |v| Verse.create!(translation: kjv, book: isaiah, chapter: 9, verse_number: v, text: "Isaiah nine verse #{v}.") }
    (1..13).each { |v| Verse.create!(translation: kjv, book: hebrews, chapter: 8, verse_number: v, text: "Hebrews eight verse #{v}.") }
    @study = @user.studies.create!(name: "Parallel", pane_count: 2)
    @study.panes.find_by(position: 0).update!(reference: "Isaiah 9", translation: kjv)
    @study.panes.find_by(position: 1).update!(reference: "Hebrews 8", translation: kjv)
  end

  test "compare offers Listen, defaults to the top passage and follows only the chosen side" do
    sign_in
    visit study_path(@study)
    wait_for_reader_js
    stub_chapter_audio
    top, bottom = all(".ps-workspace .ps-pane").map { |p| p[:id] }

    within(".ui-comparebar") { click_on "Listen" }
    assert_selector ".ui-listen-sheet.is-open"
    settle_sheet
    sides = all(".ls-side").map { |s| s.text.squish }
    assert_equal [ "Isaiah 9 · KJV Top", "Hebrews 8 · KJV Bottom" ], sides
    assert find(".ls-side", text: "Isaiah 9").find("input", visible: :all).checked?, "the top passage is chosen by default"

    find(".ls-play").click
    assert_selector "##{top} .ps-verse.is-reading", wait: 5
    assert_no_selector "##{bottom} .ps-verse.is-reading"
    assert_selector ".ui-comparebar .ui-pill.is-on", text: "Listening"
    assert_equal "/audio/chapter?osis=Isa&chapter=9", page.evaluate_script("window.__audioAsked.at(-1)")

    # Switch to the other passage: the first stops, the second plays and follows.
    within(".ui-comparebar") { click_on "Listening" }
    settle_sheet
    assert_selector ".ls-now", text: "Isaiah 9 · KJV"
    find(".ls-side", text: "Hebrews 8").click
    find(".ls-play").click
    assert_selector "##{bottom} .ps-verse.is-reading", wait: 5
    assert_no_selector "##{top} .ps-verse.is-reading"
    assert_equal "/audio/chapter?osis=Heb&chapter=8", page.evaluate_script("window.__audioAsked.at(-1)")

    # Stop from the sheet.
    within(".ui-comparebar") { click_on "Listening" }
    settle_sheet
    find(".ls-stop").click
    assert_no_selector ".ps-verse.is-reading"
    assert_selector ".ui-comparebar .ui-pill:not(.is-on)", text: "Listen"
    assert page.evaluate_script("window.__audio.paused")
  end

  test "a single passage keeps its own Listen button and no passage choice" do
    @study.update!(pane_count: 1)
    sign_in
    visit study_path(@study)
    wait_for_reader_js
    stub_chapter_audio
    find(".ps-pane [data-action~='reader#toggle']").click
    assert_selector ".ui-listen-sheet.is-open"
    settle_sheet
    assert_no_selector ".ls-sides"
    find(".ls-play").click
    assert_selector ".ps-verse.is-reading", wait: 5
    assert_equal "Stop listening", find(".ps-pane [data-action~='reader#toggle']")[:title]
  end

  private

  # Sheets slide up for ~0.25s; let them land before tapping.
  def settle_sheet = sleep(0.4)

  def sign_in
    visit new_session_path
    fill_in "email_address", with: @user.email_address
    fill_in "password", with: "password"
    click_on "Sign In"
    assert_no_current_path new_session_path
  end

  # The audio endpoint answers "ready" with a few seconds of silence made in
  # the page (no narration is generated), and each verse starts 0.5 s apart.
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
        const body = { ok: true, status: "ready", url, timings, duration: seconds, book: q.get("osis"),
                       chapter: Number(q.get("chapter")), translation: q.get("translation"), title: "Test", voice: "human" }
        return Promise.resolve(new Response(JSON.stringify(body), { headers: { "Content-Type": "application/json" } }))
      }
      const play = HTMLMediaElement.prototype.play
      HTMLMediaElement.prototype.play = function () { window.__audio = this; this.muted = true; return play.call(this) }
    JS
  end
end
