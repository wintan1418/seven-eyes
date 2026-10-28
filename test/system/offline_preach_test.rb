require "application_system_test_case"

# Phase 2 of offline support: "Get ready for Sunday", then preach with the
# Wi-Fi gone — next/prev, the Go box (chase), the queue, and the projector
# window (same device, BroadcastChannel) all keep working.
class OfflinePreachTest < ApplicationSystemTestCase
  include OfflineTestHelper

  setup do
    clear_offline_data
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    (3..4).each do |chapter|
      (1..4).each do |verse|
        Verse.create!(translation: @kjv, book: john, chapter:, verse_number: verse, text: "KJV John #{chapter}:#{verse}")
      end
    end
  end

  teardown do
    go_online
    clear_offline_data
  end

  test "after Get ready for Sunday, preach mode, chase and the projector work with no connection" do
    visit root_path
    page.execute_script("localStorage.setItem('scriptorium.tourDone', '1')")
    fill_in "reference", with: "John 3"
    click_on "Read"
    assert_selector ".ps-pane .ps-verse"
    study_path = current_path
    study = Study.find(study_path[%r{\d+}])
    study.setlist_items.create!(kind: :scripture, reference: "John 4:3")
    visit study_path
    wait_for_service_worker

    find(".ui-appbar [data-sheets-id-param='more']").click
    find(".ui-more-sheet [data-sunday-prepare]").click
    within(".ui-sunday") do
      assert_selector "li.is-ok", text: "KJV downloaded to this device", wait: 20
      assert_selector "li.is-ok", text: "2 passages ready offline", wait: 20
      assert_selector "li.is-ok", text: /projector and stage screens saved/i, wait: 20
      assert_selector "li.is-warn", text: /live follow-along and the phone remote need internet/i
    end
    find(".ps-setlist-host .ps-drawer-head .close").click

    go_offline
    find(".ui-appbar button[data-action~='presentation#start']").click
    assert_selector ".ps-root.is-preaching"
    send_keys :arrow_right
    assert_selector ".ps-pane.is-presented .ps-verse.is-preach-current[data-verse-num='2']"

    # The Go box chases a reference — parsed and rendered offline.
    send_keys "g"
    find(".ps-preach-jump input").send_keys("jn 4:2", :enter)
    assert_selector ".ps-pane.is-presented .ps-verse.is-preach-current[data-chapter='4'][data-verse-num='2']"
    assert_selector "[data-preach-counter]", text: /verse 2/i

    # The queue: present a scripture item.
    find(".ps-preach-bar [data-action~='setlist#toggle']").click
    find(".ps-setlist-item .present", text: "John 4:3").click
    assert_selector ".ps-pane.is-presented .ps-verse.is-preach-current[data-chapter='4'][data-verse-num='3']"
    find(".ps-setlist-host .ps-drawer-head .close").click if has_selector?(".ps-setlist-host.is-open", wait: 0)

    # Online-only tools say so.
    find(".ps-preach-bar .ps-golive").click
    assert_selector ".ui-offline-toast", text: /live follow-along needs internet/i
    assert_no_selector ".ps-root.is-live-session"

    # The projector screen opens from the device and follows the operator.
    operator = current_window
    projector = open_new_window
    within_window(projector) do
      visit "#{study_path}?output=1&pane=0"
      assert_selector ".ps-root.is-output"
    end
    send_keys :arrow_left
    assert_selector ".ps-pane.is-presented .ps-verse.is-preach-current[data-verse-num='2']"
    within_window(projector) do
      assert_selector ".ps-verse.is-preach-current", text: "KJV John 4:2", wait: 10
    end
    projector.close
    switch_to_window(operator)
  end

  private

  def send_keys(*keys)
    find("body").send_keys(*keys)
  end
end
