require "application_system_test_case"

# "Paste your own": NKJV pasted from the pastor's Bible app → preview of the
# slides → into the service → live on the projector and stage → Next steps verse
# by verse, with the version credit on every slide.
class PasteVersesSystemTest < ApplicationSystemTestCase
  include OfflineTestHelper

  SHOTS = ENV["SLIDE_SCREENSHOTS"].presence

  PASTE = <<~TEXT
    John 3:16-18 New King James Version

    16 For God so loved the world that He gave His only begotten[a] Son, that whoever believes in Him should not perish but have everlasting life. 17 For God did not send His Son into the world to condemn the world, but that the world through Him might be saved.
    18 “He who believes in Him is not condemned; but he who does not believe is condemned already.

    Read full chapter
    New King James Version (NKJV)
    Scripture taken from the New King James Version®. Copyright © 1982 by Thomas Nelson. Used by permission. All rights reserved.
  TEXT

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

  test "paste NKJV, preview the slides, add it, go live, Next walks the verses" do
    start_preaching
    projector = open_projector
    stage = open_stage

    find(".ps-setlist-panel").execute_script("this.scrollTop = this.scrollHeight")
    find(".ps-queue-tools button", text: "Paste verses").click
    within(".ps-tool-dialog[aria-label='Paste your own verses']") do
      assert_text "For quoting in your own service. Paste from a Bible you have the right to use."
      find(".pv-text").set(PASTE)
      # The paste names its reference and version; the junk is gone.
      assert_field "pv-ref", with: "John 3:16-18"
      assert_equal "NKJV", find("#pv-version").value
      assert_selector ".set-hint[data-tone='ok']", text: "Found 3 verses (verses 16–18)"
      assert_selector ".set-screen .set-ref", text: /John 3:16-18 \(NKJV\)/i
      assert_no_text "Copyright"
      click_on "1 verse"
      assert_selector ".set-pager .n", text: "Slide 1 of 3"
      assert_selector ".set-screen .set-words", text: "For God so loved the world that He gave His only begotten Son"
      shot "paste-form"
      click_on "Add to service"
    end
    assert_no_selector ".ps-tool-dialog[aria-label='Paste your own verses']"

    find(".ps-setlist-item", text: "John 3:16-18 NKJV").find(".present").click
    find(".ps-golive-btn").click
    assert_selector "[data-preach-slide] .set-ref", text: /John 3:16 \(NKJV\)/i
    assert_selector "[data-preach-slide] .set-words", text: /^16\s*For God so loved/
    within_window(projector) do
      assert_selector "[data-preach-slide] .set-words", text: "For God so loved the world", wait: 5
      assert_selector "[data-preach-slide] .set-ref", text: /NKJV/i
    end
    page.send_keys(:right)
    assert_selector "[data-preach-slide] .set-words", text: "For God did not send His Son"
    assert_selector "[data-preach-slide] .set-ref", text: /John 3:17 \(NKJV\)/i
    within_window(projector) { assert_selector "[data-preach-slide] .set-words", text: "For God did not send His Son", wait: 5 }
    within_window(stage) { assert_selector ".ps-stage", text: "He who believes in Him", wait: 5 } # NEXT
    page.send_keys(:right)
    assert_selector "[data-preach-slide] .set-words", text: "He who believes in Him is not condemned"
    page.send_keys(:left)
    assert_selector "[data-preach-slide] .set-words", text: "For God did not send His Son"
    assert_selector "[data-preach-slide] .set-ref", text: /John 3:17 \(NKJV\)/i

    wait_until { @study.setlist_items.scripture_set.exists? }
    ref = @study.setlist_items.scripture_set.sole.data["refs"].sole
    assert_equal [ true, "NKJV", [ 16, 17, 18 ] ], [ ref["own"], ref["translation"], ref["verses"].map { |v| v["n"] } ]
    assert_equal 1, Translation.count
    projector.close
    stage.close
  end

  test "with no signal it still adds, projects, and reaches the server once back online" do
    start_preaching
    go_offline
    find(".ps-setlist-panel").execute_script("this.scrollTop = this.scrollHeight")
    find(".ps-queue-tools button", text: "Paste verses").click
    within(".ps-tool-dialog[aria-label='Paste your own verses']") do
      fill_in "pv-ref", with: "Ps 23:1-2"
      find("#pv-version").select("Other…")
      find(".pv-other").set("tpt")
      find(".pv-text").set("¹The Lord is my best friend and my shepherd. ²He offers a resting place for me.")
      assert_selector ".set-hint[data-tone='ok']", text: "Found 2 verses"
      click_on "Add to service"
    end
    find(".ps-setlist-item", text: "TPT").find(".present").click
    find(".ps-golive-btn").click
    assert_selector "[data-preach-slide] .set-ref", text: /\(TPT\)/i
    assert_selector "[data-preach-slide] .set-words", text: "He offers a resting place"
    go_online
    wait_until { @study.setlist_items.scripture_set.exists? }
    ref = @study.setlist_items.scripture_set.sole.data["refs"].sole
    assert_equal [ "TPT", [ 1, 2 ] ], [ ref["translation"], ref["verses"].map { |v| v["n"] } ]
  end

  private

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
    prefer_focus_view
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

  def open_stage
    operator = current_window
    stage = open_new_window
    within_window(stage) do
      visit "#{study_path(@study)}?stage=1"
      assert_selector ".ps-root.is-stage .ps-stage"
    end
    switch_to_window(operator)
    stage
  end

  def wait_until(timeout: 30)
    deadline = Time.current + timeout
    until yield
      raise "timed out" if Time.current > deadline
      sleep 0.1
    end
  end

  def shot(name)
    page.save_screenshot(File.join(SHOTS, "#{name}.png")) if SHOTS
  end
end
