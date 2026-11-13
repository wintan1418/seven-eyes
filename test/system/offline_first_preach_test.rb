require "application_system_test_case"

# Offline-first preach mode. A church tester: "If I type John 3:16 while
# offline it takes up to 20 secs" — his phone had data bars but no data, so
# every lookup waited on a network that never answered. Now references are
# read on the device and passages come from the downloaded Bible first.
class OfflineFirstPreachTest < ApplicationSystemTestCase
  include OfflineTestHelper

  setup do
    clear_offline_data
    @user = users(:one)
    @user.update!(tour_completed_at: Time.current)
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    mark = Book.create!(osis_code: "Mark", name: "Mark", testament: :new, position: 41, chapter_count: 16)
    (3..4).each do |chapter|
      (1..18).each do |verse|
        Verse.create!(translation: @kjv, book: john, chapter:, verse_number: verse, text: "KJV John #{chapter}:#{verse}")
      end
    end
    Verse.create!(translation: @kjv, book: mark, chapter: 15, verse_number: 15,
                  text: "And Pilate delivered Jesus, when he had scourged him, to be crucified.")
    @study = @user.studies.create!(name: "Sunday", pane_count: 1)
    @study.panes.first.update!(reference: "John 4", translation: @kjv)
  end

  teardown do
    go_online
    clear_offline_data
  end

  test "a presenter's Bible downloads itself, then a reference goes on screen at once with a dead signal" do
    sign_in
    visit study_path(@study)
    wait_for_service_worker
    wait_for_reader_js

    # Entering preach downloads the study's Bible (whole translation) for offline.
    find(".ui-appbar button[data-action~='presentation#start']").click
    assert_selector ".ps-root.is-preaching"
    assert_selector ".ps-preach-offline[data-state='ready']", text: /ready offline.*whole KJV/i, wait: 20
    assert_match(/Whole KJV Bible saved on this device \(\d+ books?\)/, find(".ps-preach-offline")["title"])

    # The projector window, opened while the network was fine.
    operator = current_window
    projector = open_new_window
    within_window(projector) do
      visit "#{study_path(@study)}?output=1&pane=0"
      assert_selector ".ps-root.is-output .ps-verse.is-preach-current"
    end
    switch_to_window(operator)

    # Data on, nothing coming back.
    go_dead_network
    find("body").send_keys("g")
    input = find(".ps-preach-jump input")
    input.send_keys("john 3 16")
    assert_selector ".ps-preach-jump-hint", text: "John 3:16", wait: 1 # parsed on the device
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    input.send_keys(:enter)
    assert_selector ".ps-pane.is-presented .ps-verse.is-preach-current[data-chapter='3'][data-verse-num='16']", wait: 2
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    assert elapsed < 2, "took #{elapsed.round(2)} s with a dead network"
    within_window(projector) do
      assert_selector ".ps-verse.is-preach-current", text: "KJV John 3:16", wait: 3
    end

    # A described thought: the AI can't be reached, so the downloaded Bible is searched.
    find("body").send_keys("g")
    find(".ps-preach-jump input").send_keys("Jesus scourged", :enter)
    within(".ps-preach-finds") do
      assert_text(/offline search \(keywords\)/i, wait: 6)
      find(".find .pick", text: /Mark 15:15/i).click
    end
    # A result goes to Preview first; L puts it on the screen.
    assert_selector ".ps-console-preview .what", text: "Mark 15:15"
    find("body").send_keys("l")
    assert_selector ".ps-pane.is-presented .ps-verse.is-preach-current[data-osis='Mark'][data-verse-num='15']", wait: 2

    go_online
    projector.close
    switch_to_window(operator)
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
