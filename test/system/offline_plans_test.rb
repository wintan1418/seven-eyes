require "application_system_test_case"

# Phase 3 of offline support: a reading plan with no signal — tick a day
# (synced later) and open today's reading from the downloaded Bible.
class OfflinePlansTest < ApplicationSystemTestCase
  include OfflineTestHelper

  setup do
    clear_offline_data
    @user = users(:one)
    @user.update!(tour_completed_at: Time.current)
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    (3..5).each do |chapter|
      (1..3).each { |v| Verse.create!(translation: @kjv, book: john, chapter:, verse_number: v, text: "KJV John #{chapter}:#{v}") }
    end
    @study = @user.studies.create!(name: "Plan: Gospel", pane_count: 1)
    @study.panes.first.update!(reference: "John 3", translation: @kjv)
    @plan = @user.reading_plans.create!(name: "Gospel", start_date: Date.current, study: @study)
    @today = @plan.plan_days.create!(day_number: 1, refs: "John 4")
    @plan.plan_days.create!(day_number: 2, refs: "John 5")
  end

  teardown do
    go_online
    clear_offline_data
  end

  test "tick today's reading and open it with no connection; the tick syncs later" do
    sign_in
    visit offline_path(from: study_path(@study))
    download_bible("KJV")
    visit reading_plan_path(@plan)
    wait_for_service_worker
    wait_for_saved_page(reading_plan_path(@plan))
    wait_for_saved_page(study_path(@study))

    go_offline
    visit reading_plan_path(@plan) # opens from the device
    within("##{ActionView::RecordIdentifier.dom_id(@today)}") { click_on "Mark done" }
    assert_selector "##{ActionView::RecordIdentifier.dom_id(@today)}.is-done", text: /✓ Done/i
    assert_selector ".ps-sync-pill", text: "1 change waiting to sync"
    assert_equal 0, PlanCompletion.count

    click_on "Begin today's reading"
    assert_selector ".ps-verse-text", text: "KJV John 4:1"
    assert_selector ".ui-appbar [data-reader-header-target='reference']", text: "John 4"

    go_online
    assert_selector ".ps-sync-pill", text: "All changes saved", wait: 10
    assert @today.reload.completed?
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
