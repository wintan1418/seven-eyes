require "application_system_test_case"

# Search results honour Preview. A church tester (offline, "13 changes waiting
# to sync"): typing "psalm 133" and pressing PREVIEW staged it in Preview, but
# typing words ("faith of the son") and pressing PREVIEW opened the search
# results — and clicking Galatians 2:20 there put it straight on the projector.
# "I should decide if it should go live or not." Now nothing from a search
# goes on the screen without an explicit live action: a result row previews,
# and only L / Go live / the row's own Go live (or double-click, Shift+Enter)
# changes the projector.
class PreachSearchPreviewTest < ApplicationSystemTestCase
  include OfflineTestHelper

  GAL_2_20 = "I am crucified with Christ: nevertheless I live; yet not I, but Christ liveth in me: and the life " \
             "which I now live in the flesh I live by the faith of the Son of God, who loved me, and gave himself for me."
  MATT_11_12 = "And from the days of John the Baptist until now the kingdom of heaven suffereth violence, " \
               "and the violent take it by force."
  MATT_5_3 = "Blessed are the poor in spirit: for theirs is the kingdom of heaven."

  setup do
    clear_offline_data
    @user = users(:one)
    @user.update!(tour_completed_at: Time.current)
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    (30..36).each { |v| Verse.create!(translation: @kjv, book: john, chapter: 11, verse_number: v, text: "KJV John 11:#{v}") }
    gal = Book.create!(osis_code: "Gal", name: "Galatians", testament: :new, position: 48, chapter_count: 6)
    (19..21).each do |v|
      Verse.create!(translation: @kjv, book: gal, chapter: 2, verse_number: v, text: v == 20 ? GAL_2_20 : "KJV Galatians 2:#{v}")
    end
    matt = Book.create!(osis_code: "Matt", name: "Matthew", testament: :new, position: 40, chapter_count: 28)
    Verse.create!(translation: @kjv, book: matt, chapter: 5, verse_number: 3, text: MATT_5_3)
    (11..13).each do |v|
      Verse.create!(translation: @kjv, book: matt, chapter: 11, verse_number: v, text: v == 12 ? MATT_11_12 : "KJV Matthew 11:#{v}")
    end
    @study = @user.studies.create!(name: "Sunday", pane_count: 1)
    @study.panes.first.update!(reference: "John 11", translation: @kjv)
    @original_search = PulpitSearch.method(:call)
  end

  teardown do
    PulpitSearch.define_singleton_method(:call, @original_search)
    go_online
    clear_offline_data
  end

  test "dead network: words + PREVIEW → a keyword result goes to Preview, the projector waits for L" do
    start_preaching
    projector = open_projector
    go_dead_network
    watch_projector(projector)

    find("body").send_keys("g")
    find(".ps-preach-jump input").send_keys("faith of the son")
    find(".ps-preach-jump-preview").click
    within(".ps-preach-finds") do
      assert_text(/offline search \(keywords\)/i, wait: 8)
      assert_selector "[data-finds-mode='preview']", text: "Results go to Preview"
      find(".find .pick", text: /Galatians 2:20/i).click
    end

    assert_selector ".ps-console-preview[data-state='ready'] .what", text: "Galatians 2:20"
    assert_selector ".ps-preview-text", text: "faith of the Son of God"
    assert_selector ".ps-preach-finds .find.is-preview", text: /Galatians 2:20/i
    sleep 0.6
    assert_equal 0, projector_changes(projector), "a search result changed the projector"
    within_window(projector) { assert_selector ".ps-verse.is-preach-current", text: "KJV John 11:30" }
    assert_selector ".ps-pane.is-presented .ps-verse.is-preach-current[data-osis='John'][data-verse-num='30']"

    find("body").send_keys("l")
    within_window(projector) { assert_selector ".ps-verse.is-preach-current", text: "faith of the Son of God", wait: 3 }
    assert_selector ".ps-console-row.is-live .what", text: "Galatians 2:20"
    assert_no_selector ".ps-preach-finds", visible: true

    # What went live joined the queue on the device; it syncs once the signal is back.
    go_online
    wait_until { @study.setlist_items.exists? }
    projector.close
  end

  test "AI quick find (Shift+Enter): ↑/↓ and Enter preview a result, the card previews as a slide, L goes live" do
    stub_ai
    start_preaching
    projector = open_projector
    watch_projector(projector)

    find("body").send_keys("g")
    find(".ps-preach-jump input").send_keys("faith of the son", [ :shift, :enter ])
    within(".ps-preach-finds") do
      assert_text(/study assistant/i, wait: 5)
      assert_selector "[data-finds-mode='preview']", text: "Results go to Preview"
      assert_selector ".find", count: 2
    end
    # The keyboard is on the first result: ↓ then Enter previews the second.
    page.send_keys(:down, :enter)
    assert_selector ".ps-console-preview .what", text: "Matthew 11:12"
    assert_selector ".ps-preview-text", text: "suffereth violence"

    # The answer card previews too — it never jumps to the screen on its own.
    find(".ps-preach-finds .card .project", text: /preview this card/i).click
    assert_selector ".ps-console-preview .what", text: "Faith in the Son of God"
    sleep 0.6
    assert_equal 0, projector_changes(projector), "a search result changed the projector"

    # Back to the verse, then L.
    find(".ps-preach-finds .find .pick", text: /Matthew 11:12/i).click
    assert_selector ".ps-console-preview .what", text: "Matthew 11:12"
    sleep 0.3
    assert_equal 0, projector_changes(projector)
    find("body").send_keys("l")
    within_window(projector) { assert_selector ".ps-verse.is-preach-current", text: "suffereth violence", wait: 3 }
    projector.close
  end

  test "no signal, Preview first on: Enter searches, Enter previews a result, Shift+Enter puts the next one live" do
    start_preaching
    projector = open_projector
    go_offline
    watch_projector(projector)

    find("body").send_keys("g")
    find(".ps-preach-jump [data-preview-first]").click
    assert_selector ".ps-preach-jump [data-preview-first][aria-pressed='true']"
    find(".ps-preach-jump input").send_keys("kingdom of heaven", :enter)
    within(".ps-preach-finds") do
      assert_text(/offline search \(keywords\)/i, wait: 8)
      assert_selector "[data-finds-mode='preview']", text: "Results go to Preview"
      assert_selector ".find", minimum: 2
    end
    first_ref, second_ref = all(".ps-preach-finds .find").first(2).map { |row| row["data-reference"] }

    page.send_keys(:enter)
    assert_selector ".ps-console-preview .what", text: first_ref
    sleep 0.6
    assert_equal 0, projector_changes(projector), "a search result changed the projector"
    within_window(projector) { assert_selector ".ps-verse.is-preach-current", text: "KJV John 11:30" }

    page.send_keys(:down, [ :shift, :enter ])
    verse = second_ref[/\d+\z/]
    assert_selector ".ps-pane.is-presented .ps-verse.is-preach-current[data-osis='Matt'][data-verse-num='#{verse}']", wait: 3
    within_window(projector) { assert_selector ".ps-verse.is-preach-current[data-verse-num='#{verse}']", wait: 3 }
    projector.close
  end

  test "a search started with GO: the row previews; its Go live, or a double-click, goes live; + Queue queues" do
    stub_ai
    start_preaching
    projector = open_projector
    watch_projector(projector)

    find("body").send_keys("g")
    find(".ps-preach-jump input").send_keys("faith of the son", :enter)
    assert_selector ".ps-preach-finds [data-finds-mode='preview']", text: "Results go to Preview", wait: 5

    find(".ps-preach-finds .find .pick", text: /Galatians 2:20/i).click
    assert_selector ".ps-console-preview .what", text: "Galatians 2:20"
    sleep 0.6
    assert_equal 0, projector_changes(projector), "a search result changed the projector"
    within_window(projector) { assert_selector ".ps-verse.is-preach-current", text: "KJV John 11:30" }

    # + Queue: into the queue, nothing on screen.
    find(".ps-preach-finds .find", text: /Galatians 2:20/i).find(".queue").click
    assert_selector ".ps-setlist-item .lbl", text: "Galatians 2:20"
    assert_equal 0, projector_changes(projector)

    # The row's own Go live.
    find(".ps-preach-finds .find", text: /Matthew 11:12/i).find(".golive").click
    within_window(projector) { assert_selector ".ps-verse.is-preach-current", text: "suffereth violence", wait: 3 }
    assert_no_selector ".ps-preach-finds", visible: true

    # Double-click goes live too.
    find("body").send_keys("g")
    find(".ps-preach-jump input").send_keys("faith of the son", :enter)
    find(".ps-preach-finds .find .pick", text: /Galatians 2:20/i, wait: 5).double_click
    within_window(projector) { assert_selector ".ps-verse.is-preach-current", text: "faith of the Son of God", wait: 3 }
    projector.close
  end

  private

  def stub_ai
    gal, matt = GAL_2_20, MATT_11_12
    PulpitSearch.define_singleton_method(:call) do |*_args, **_kw|
      PulpitSearch::Result.new(
        ok: true, topic: "Faith in the Son of God",
        summary: "Paul says the life he now lives, he lives by the faith of the Son of God.",
        suggestions: [
          PulpitSearch::Suggestion.new(reference: "Galatians 2:20", osis: "Gal", chapter: 2, verse_start: 20, verse_end: 20, preview: gal),
          PulpitSearch::Suggestion.new(reference: "Matthew 11:12", osis: "Matt", chapter: 11, verse_start: 12, verse_end: 12, preview: matt)
        ])
    end
  end

  def wait_until(timeout: 30)
    Timeout.timeout(timeout) { sleep 0.2 until yield }
  end

  # Count every change of what the projector shows (verse or slide).
  def watch_projector(projector)
    within_window(projector) do
      page.execute_script(<<~JS)
        window.__changes = 0
        const root = document.querySelector(".ps-root")
        new MutationObserver(() => { window.__changes++ }).observe(root, { subtree: true, childList: true, attributes: true, attributeFilter: ["class"] })
      JS
    end
  end

  def projector_changes(projector)
    within_window(projector) { page.evaluate_script("window.__changes") }
  end

  def sign_in
    visit new_session_path
    fill_in "email_address", with: @user.email_address
    fill_in "password", with: "password"
    click_on "Sign In"
    assert_no_current_path new_session_path
  end

  # Signed in, study open, preach mode on with the study's Bible downloaded.
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
      assert_selector ".ps-root.is-output .ps-verse.is-preach-current", text: "KJV John 11:30"
    end
    switch_to_window(operator)
    projector
  end
end
