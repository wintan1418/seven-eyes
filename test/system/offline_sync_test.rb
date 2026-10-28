require "application_system_test_case"

# Phase 4 of offline support: notes and highlights made with no signal wait
# in the outbox and sync when the connection is back — without overwriting
# notes that changed elsewhere meanwhile.
class OfflineSyncTest < ApplicationSystemTestCase
  include OfflineTestHelper

  setup do
    clear_offline_data
    @user = users(:one)
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    @verse = Verse.create!(translation: @kjv, book: john, chapter: 3, verse_number: 16, text: "For God so loved the world")
    Verse.create!(translation: @kjv, book: john, chapter: 3, verse_number: 17, text: "For God sent not his Son")
    Verse.create!(translation: @kjv, book: john, chapter: 4, verse_number: 1, text: "When therefore the Lord knew")
    @study = @user.studies.create!(name: "John", pane_count: 1)
    @pane = @study.panes.first
    @pane.update!(reference: "John 3", translation: @kjv, notes: "Server text")
    @user.update!(tour_completed_at: Time.current)
  end

  teardown do
    go_online
    clear_offline_data
  end

  test "a note typed and a verse highlighted offline sync when the connection returns" do
    get_ready

    go_offline
    open_notes
    area = find(".ps-notes-area")
    area.send_keys(:end, " — written on the bus")
    assert_selector "[data-notes-target='status']", text: /saved on this device/i, wait: 5
    assert_selector ".ps-sync-pill", text: "1 change waiting to sync"

    tap_verse(16)
    find(".ui-actionbar button[aria-label='Highlight ochre']").click
    assert_selector ".ps-verse[data-verse-num='16'] .hl-ochre[data-highlight-id^='tmp-']", text: "For God so loved the world"
    assert_selector ".ps-sync-pill", text: "2 changes waiting to sync"

    # Still offline: the next chapter and back keep the offline highlight.
    find(".rd-chapter-nav .rd-fab.next").click
    assert_selector ".ps-verse-text", text: "When therefore the Lord knew"
    find(".rd-chapter-nav .rd-fab.prev").click
    assert_selector ".ps-verse[data-verse-num='16'] .hl-ochre"

    assert_equal "Server text", @pane.reload.notes
    assert_equal 0, @user.highlights.count

    go_online
    assert_selector ".ps-sync-pill", text: "All changes saved", wait: 10
    highlight = @user.highlights.sole
    assert_equal [ "ochre", 0, 26 ], [ highlight.color, highlight.char_start, highlight.char_end ]
    assert_selector ".ps-verse[data-verse-num='16'] .hl-ochre[data-highlight-id='#{highlight.id}']"
    assert_equal "Server text — written on the bus", @pane.reload.notes
  end

  test "an offline note never overwrites notes changed elsewhere meanwhile" do
    get_ready

    go_offline
    open_notes
    find(".ps-notes-area").send_keys(:end, " + offline")
    assert_selector "[data-notes-target='status']", text: /saved on this device/i, wait: 5
    assert_selector ".ps-sync-pill", text: "1 change waiting to sync"

    @pane.update!(notes: "Edited on the laptop") # another device, while this one is offline

    go_online
    assert_selector ".ps-sync-pill", text: "All changes saved", wait: 10
    notes = @pane.reload.notes
    assert_match(/\AEdited on the laptop\n\n— Offline edit \(\w+ \d+, \d{4}\) —\nServer text \+ offline\z/, notes)
    assert_equal notes, find(".ps-notes-area").value
    assert_selector ".ui-offline-toast", text: /added below/i
  end

  test "guests offline get the create-an-account prompt, as online" do
    visit root_path
    page.execute_script("localStorage.setItem('scriptorium.tourDone', '1')")
    fill_in "reference", with: "John 3"
    click_on "Read"
    assert_selector ".ps-pane .ps-verse"
    study_path = current_path
    visit offline_path(from: study_path)
    download_bible("KJV")
    visit study_path
    wait_for_service_worker

    go_offline
    tap_verse(16)
    find(".ui-actionbar button[aria-label='Highlight ochre']").click
    assert_selector ".ps-auth-modal.is-open", wait: 3
  end

  private

  def get_ready
    sign_in
    visit offline_path(from: study_path(@study))
    download_bible("KJV")
    visit study_path(@study)
    wait_for_service_worker
    wait_for_reader_js
  end

  def open_notes
    3.times do
      find(".ps-pane-tool[title='Notes']").click
      break if has_selector?(".ps-notes-form.is-open", wait: 1)
    end
    assert_selector ".ps-notes-form.is-open"
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
