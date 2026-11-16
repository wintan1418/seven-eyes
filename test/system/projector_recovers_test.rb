require "application_system_test_case"

# A church tester, mid-meeting: Luke 1:77-79 went up on the operator but the
# projector stayed on Luke 1:22 — clearing and trying again changed nothing.
# One passage load on the projector had failed (a weak connection); it had
# already written the new passage into its form, so every later state looked
# "already loaded" and it never fetched again. A failed load must not stick.
class ProjectorRecoversTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @user.update!(tour_completed_at: Time.current, guide_dismissed_at: Time.current)
    kjv = Translation.create!(code: "KJV", name: "King James Version")
    luke = Book.create!(osis_code: "Luke", name: "Luke", testament: :new, position: 42, chapter_count: 24)
    john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    (1..80).each { |v| Verse.create!(translation: kjv, book: luke, chapter: 1, verse_number: v, text: "Luke one verse #{v}") }
    (1..5).each { |v| Verse.create!(translation: kjv, book: john, chapter: 3, verse_number: v, text: "John three verse #{v}") }
    @study = @user.studies.create!(name: "Meeting", pane_count: 1)
    @study.panes.first.update!(reference: "John 3", translation: kjv)
  end

  test "a projector whose passage load failed fetches it again on the next verse" do
    sign_in
    visit study_path(@study)
    wait_for_reader_js
    prefer_focus_view
    find(".ui-appbar button[data-action~='presentation#start']").click
    assert_selector ".ps-root.is-preaching"
    projector = open_projector
    within_window(projector) { assert_selector ".ps-verse.is-preach-current", text: "John three verse 1", wait: 5 }

    # The projector's next passage load fails (a dropped connection, a
    # Bible half-downloaded): the pane reports an error and nothing changes.
    within_window(projector) do
      page.execute_script(<<~JS)
        const root = document.querySelector(".ps-root")
        const ctl = window.Stimulus.getControllerForElementAndIdentifier(root, "presentation")
        const real = ctl._submitPane.bind(ctl)
        let failed = false
        ctl._submitPane = (pane, opts) => {
          if (failed) return real(pane, opts)
          failed = true
          setTimeout(() => pane.dispatchEvent(new CustomEvent("turbo:fetch-request-error", { bubbles: true })), 50)
        }
      JS
    end

    go_to "Luke 1:22"
    assert_selector ".ps-pane.is-presented .ps-verse.is-preach-current", text: "Luke one verse 22", wait: 5
    # The projector tries again by itself…
    within_window(projector) { assert_selector ".ps-verse.is-preach-current", text: "Luke one verse 22", wait: 10 }

    # …and keeps following.
    go_to "Luke 1:77"
    assert_selector ".ps-pane.is-presented .ps-verse.is-preach-current", text: "Luke one verse 77", wait: 5
    within_window(projector) do
      assert_selector ".ps-verse.is-preach-current", text: "Luke one verse 77", wait: 15
    end
  end

  private

  def sign_in
    visit new_session_path
    fill_in "email_address", with: @user.email_address
    fill_in "password", with: "password"
    click_on "Sign In"
    assert_no_current_path new_session_path
  end

  def open_projector
    operator = current_window
    win = open_new_window
    within_window(win) do
      visit "#{study_path(@study)}?output=1&pane=0"
      assert_selector ".ps-root.is-output"
    end
    switch_to_window(operator)
    win
  end

  def go_to(reference)
    find("body").send_keys("g")
    find(".ps-preach-jump input").fill_in(with: reference).send_keys(:enter)
  end
end
