require "application_system_test_case"

# The song bank, built for a church tester who runs EasyWorship: find a hymn by
# its title or a line of its words, drop it in the queue, and project it with
# the chorus coming back after every verse — the chorus typed once. Songs can
# be pasted in from anywhere (labels found for you), given an order
# ("V1 C V2 C B C"), saved to "My songs", and all of it works with no signal.
class SongBankTest < ApplicationSystemTestCase
  include OfflineTestHelper

  SHOTS = ENV["SONG_SCREENSHOTS"].presence

  setup do
    clear_offline_data
    @user = users(:one)
    @user.update!(tour_completed_at: Time.current)
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    (1..4).each { |v| Verse.create!(translation: @kjv, book: john, chapter: 3, verse_number: v, text: "KJV John 3:#{v}") }
    @study = @user.studies.create!(name: "Sunday", pane_count: 1)
    @study.panes.first.update!(reference: "John 3", translation: @kjv)
  end

  teardown do
    go_online
    clear_offline_data
  end

  test "search the hymnal by a line of the words, add it, and project it with the chorus after every verse" do
    start_preaching
    projector = open_projector

    open_song_bank
    within(".ps-song-bank") do
      assert_selector ".bank-sources [data-source='hymnal'] .n", text: Hymnal::HYMNS.size.to_s
      find(".bank-search").send_keys("foretaste of glory")
      assert_selector ".bank-row", count: 1
      assert_selector ".bank-row.is-picked .t", text: "Blessed Assurance"
      assert_selector ".bank-row .line", text: "foretaste of glory divine"
      assert_selector ".bank-row .author", text: "Fanny J. Crosby"
      assert_selector ".bank-row .rights", text: /public domain/i
      assert_selector ".bank-preview .flow", text: "Projects as V1 C V2 C V3 C"
      assert_selector ".bank-preview .sec .lbl", text: /chorus/i
    end
    shot "song-bank-search"
    find(".ps-song-bank .bank-search").send_keys(:enter) # Enter adds the picked song
    assert_selector ".ps-song-bank .status", text: "Added “Blessed Assurance” to the queue"
    find(".ps-song-bank .bank-search").send_keys(:escape)
    assert_no_selector ".ps-song-bank"

    item = find(".ps-setlist-item", text: "Blessed Assurance")
    assert_selector ".ps-setlist-item .meta", text: /6 slides/i

    # Preview lists every slide with its section; nothing on the projector yet.
    item.find(".present").click
    within(".ps-console-preview") do
      assert_selector ".ps-preview-text .slide", count: 6
      assert_equal [ "VERSE 1", "CHORUS", "VERSE 2", "CHORUS", "VERSE 3", "CHORUS" ],
                   all(".ps-preview-text .slide .lbl").map(&:text).map(&:upcase)
    end
    within_window(projector) { assert_no_selector "[data-preach-slide]", text: "Blessed assurance" }

    find(".ps-golive-btn").click
    within_window(projector) { assert_selector "[data-preach-slide] .slide-stanza", text: "Blessed assurance, Jesus is mine!", wait: 3 }
    assert_selector "[data-preach-counter] .num", text: /verse 1/i

    page.send_keys(:right)
    within_window(projector) { assert_selector "[data-preach-slide] .slide-stanza", text: "This is my story, this is my song", wait: 3 }
    assert_selector "[data-preach-counter]", text: /chorus/i
    assert_selector "[data-preach-next]", text: /next · verse 2/i
    shot "operator-chorus-live"
    within_window(projector) do
      assert_no_selector "[data-preach-slide]", text: "CHORUS" # labels never go on the big screen
      shot "projected-chorus"
    end

    page.send_keys(:right, :right) # verse 2 → the chorus again
    within_window(projector) { assert_selector "[data-preach-slide] .slide-stanza", text: "This is my story, this is my song", wait: 3 }
    assert_selector "[data-preach-counter] .of", text: /4 of 6/i
    assert_selector ".ps-preview-text .slide.is-live[data-index='3']"

    # A slide in Preview's list jumps straight there (the congregation went back to verse 1).
    find(".ps-preview-text .slide[data-index='0']").click
    within_window(projector) { assert_selector "[data-preach-slide] .slide-stanza", text: "Blessed assurance, Jesus is mine!", wait: 3 }

    wait_until { @study.setlist_items.song.count == 1 }
    assert_equal 6, @study.setlist_items.song.first.stanzas.size
    projector.close
  end

  test "paste a song, give it an order, save it to my songs, and find it again offline" do
    start_preaching
    pick_song_kind
    pasted = "Great Is Our God Today\n\nVerse 1\nWe lift our hands\nWe lift our voice\n\nChorus:\nGreat is our God (x2)\n\nVerse 2\nHe made the sea\n\nBridge\nHallelujah\n\nRepeat Chorus"
    paste_into(".ps-setlist-form .body-field", pasted)
    assert_equal "Great Is Our God Today", find(".ps-setlist-form .title-field").value
    assert_equal "[Verse 1]\nWe lift our hands\nWe lift our voice\n\n[Chorus]\nGreat is our God (x2)\n\n[Verse 2]\nHe made the sea\n\n[Bridge]\nHallelujah\n\n[Chorus]",
                 find(".ps-setlist-form .body-field").value
    assert_selector ".ps-setlist-form .song-flow", text: "5 slides · projects as V1 C V2 B C"
    assert_selector ".ps-setlist-form .song-note", text: "Pasted and tidied"

    find(".ps-setlist-form .order-field").set("V1 C V2 C B C C")
    assert_selector ".ps-setlist-form .song-flow", text: "7 slides · projects as V1 C V2 C B C C"
    find(".ps-setlist-form .order-field").set("V1 C V9")
    assert_selector ".ps-setlist-form .song-flow[data-tone='error']", text: "not in this song: v9"
    find(".ps-setlist-form .order-field").set("V1 C V2 C B C")
    find(".ps-setlist-panel").execute_script("this.scrollTop = this.scrollHeight")
    shot "song-editor"

    click_on "Save to my songs"
    assert_selector ".ps-setlist-form .song-note", text: "Saved “Great Is Our God Today” to your songs"
    wait_until { @user.songs.exists?(title: "Great Is Our God Today") }
    assert_equal "V1 C V2 C B C", @user.songs.sole.arrangement

    find(".ps-setlist-form .add").click
    assert_selector ".ps-setlist-item", text: "Great Is Our God Today"
    assert_selector ".ps-setlist-item .meta", text: /6 slides/i

    # The bank was saved on the device: search it, and queue from it, offline.
    open_song_bank
    assert_selector ".ps-song-bank .bank-row", minimum: 10
    find(".ps-song-bank .close").click
    go_offline
    open_song_bank
    within(".ps-song-bank") do
      find(".bank-search").send_keys("great is our god")
      find(".bank-sources [data-source='yours']").click
      assert_selector ".bank-row", count: 1
      assert_selector ".bank-row .rights", text: /yours/i
      assert_selector ".bank-preview .flow", text: "Projects as V1 C V2 C B C"
      find(".bank-row .edit").click # "Edit first" opens it in the song editor
    end
    assert_no_selector ".ps-song-bank"
    assert_equal "V1 C V2 C B C", find(".ps-setlist-form .order-field").value
    assert_match(/\A\[Verse 1\]/, find(".ps-setlist-form .body-field").value)
  end

  private

  def open_song_bank
    pick_song_kind
    find(".ps-song-library .lib-toggle").click
    assert_selector ".ps-song-bank .bank-search:focus"
    assert_selector ".ps-song-bank .bank-row", minimum: 1, wait: 10
  end

  # The queue column scrolls under the sticky live/preview console.
  def pick_song_kind
    find(".ps-setlist-panel").execute_script("this.scrollTop = this.scrollHeight")
    label = find(".ps-setlist-form .kinds label", text: /song/i)
    label.click unless label[:class].to_s.include?("is-on")
  end

  # A real paste: the editor tidies the clipboard text.
  def paste_into(selector, text)
    find(selector).click
    page.execute_script(<<~JS, selector, text)
      const [sel, text] = arguments
      const field = document.querySelector(sel)
      const data = new DataTransfer()
      data.setData("text/plain", text)
      field.dispatchEvent(new ClipboardEvent("paste", { clipboardData: data, bubbles: true, cancelable: true }))
    JS
  end

  def sign_in
    visit new_session_path
    fill_in "email_address", with: @user.email_address
    fill_in "password", with: "password"
    click_on "Sign In"
    assert_no_current_path new_session_path
  end

  def start_preaching
    sign_in
    visit study_path(@study)
    wait_for_service_worker
    wait_for_reader_js
    prefer_focus_view # these tests drive the full-screen slide (Focus view)
    find(".ui-appbar button[data-action~='presentation#start']").click
    assert_selector ".ps-root.is-preaching"
    assert_selector ".ps-preach-offline[data-state='ready']", wait: 20
  end

  def open_projector
    operator = current_window
    projector = open_new_window
    within_window(projector) do
      visit "#{study_path(@study)}?output=1&pane=0"
      assert_selector ".ps-root.is-output .ps-verse.is-preach-current"
    end
    switch_to_window(operator)
    projector
  end

  def wait_until(timeout: 30)
    Timeout.timeout(timeout) { sleep 0.2 until yield }
  end

  def shot(name)
    page.save_screenshot(File.join(SHOTS, "#{name}.png")) if SHOTS
  end
end
