require "application_system_test_case"

# Phase 1 of offline support: download a Bible to the device, lose the
# connection, and keep reading — chapters, versions, prev/next, typed
# references — rendered by the service worker from IndexedDB.
class OfflineReadingTest < ApplicationSystemTestCase
  include OfflineTestHelper

  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @bsb = Translation.create!(code: "BSB", name: "Berean Standard Bible")
    Translation.create!(code: "NET", name: "NET Bible") # licence-restricted: never offered for download
    john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    (2..4).each do |chapter|
      (1..3).each do |verse|
        Verse.create!(translation: @kjv, book: john, chapter:, verse_number: verse, text: "KJV John #{chapter}:#{verse}")
        Verse.create!(translation: @bsb, book: john, chapter:, verse_number: verse, text: "BSB John #{chapter}:#{verse}")
      end
    end
  end

  setup { clear_offline_data }

  teardown do
    go_online
    clear_offline_data
  end

  test "download a translation, go offline, then read: next/prev chapter, switch version, type a reference" do
    study_path = open_reader("John 3")

    visit offline_path(from: study_path)
    assert_no_selector ".ui-offline-row[data-code='NET']"
    download_bible("KJV")
    download_bible("BSB")

    visit study_path
    wait_for_service_worker
    wait_for_saved_page(study_path)
    assert_selector ".ps-verse-text", text: "KJV John 3:1"

    go_offline
    assert_selector ".ps-offline-badge", text: /reading from your downloads/i

    find(".rd-chapter-nav .rd-fab.next").click
    assert_selector ".ps-verse-text", text: "KJV John 4:2"
    assert_selector ".ui-appbar [data-reader-header-target='reference']", text: "John 4"
    # Same markup contract as the server: verse hooks the reader and preach mode use.
    assert_selector ".ps-verse[data-osis='John'][data-chapter='4'][data-verse-num='3'] .ps-verse-text[data-verse-id][data-offset-base='0']"

    find(".ui-appbar [data-sheets-id-param='translation']").click
    within(".ui-translation-sheet") { find(".ui-option", text: "BSB").click }
    assert_selector ".ps-verse-text", text: "BSB John 4:1"
    assert_selector ".ui-appbar [data-reader-header-target='translation']", text: "BSB"

    find(".rd-chapter-nav .rd-fab.prev").click
    assert_selector ".ps-verse-text", text: "BSB John 3:1"

    find(".ui-appbar [data-sheets-id-param='passage']").click
    within(".ui-passage-sheet") do
      find("input[type=search]").fill_in(with: "jn 2:2")
      find("input[type=search]").send_keys(:enter)
    end
    assert_selector ".ps-verse-text", text: "BSB John 2:2"
    assert_selector ".ps-verse", count: 1

    # Online-only features say so instead of failing silently.
    find(".ps-vnum", text: "2").click
    assert_selector ".ui-offline-toast", text: /need internet/i

    # The app itself opens with no signal.
    visit study_path
    assert_selector ".ps-verse-text", text: "KJV John 3:1"
  end

  test "a Bible that isn't downloaded explains itself offline" do
    study_path = open_reader("John 3")
    visit offline_path(from: study_path)
    download_bible("KJV")
    visit study_path
    wait_for_service_worker

    go_offline
    find(".ui-appbar [data-sheets-id-param='translation']").click
    within(".ui-translation-sheet") { find(".ui-option", text: "BSB").click }
    assert_selector ".ps-pane-empty", text: /BSB isn.t downloaded/i
    click_on "Show in KJV"
    assert_selector ".ps-verse-text", text: "KJV John 3:1"
  end

  private

  def open_reader(reference)
    visit root_path
    page.execute_script("localStorage.setItem('scriptorium.tourDone', '1')")
    fill_in "reference", with: reference
    click_on "Read"
    assert_selector ".ps-pane .ps-verse"
    current_path
  end
end
