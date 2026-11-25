require "application_system_test_case"

# Next / Prev carry on across chapters AND books in both directions
# (Trello UTnFW9OO): Malachi 4:6 ⇄ Matthew 1:1, Genesis 50:26 ⇄ Exodus 1:1.
class PreachContinuationTest < ApplicationSystemTestCase
  include OfflineTestHelper

  setup do
    clear_offline_data
    @user = users(:one)
    @user.update!(tour_completed_at: Time.current)
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    gen = Book.create!(osis_code: "Gen", name: "Genesis", testament: :old, position: 1, chapter_count: 50)
    exod = Book.create!(osis_code: "Exod", name: "Exodus", testament: :old, position: 2, chapter_count: 40)
    mal = Book.create!(osis_code: "Mal", name: "Malachi", testament: :old, position: 39, chapter_count: 4)
    matt = Book.create!(osis_code: "Matt", name: "Matthew", testament: :new, position: 40, chapter_count: 28)
    {
      [ gen, 1 ] => { 1 => "In the beginning God created the heaven and the earth.", 2 => "And the earth was without form, and void" },
      [ gen, 50 ] => { 25 => "And Joseph took an oath of the children of Israel", 26 => "So Joseph died, being an hundred and ten years old" },
      [ exod, 1 ] => { 1 => "Now these are the names of the children of Israel", 2 => "Reuben, Simeon, Levi, and Judah" },
      [ mal, 4 ] => { 5 => "Behold, I will send you Elijah the prophet", 6 => "And he shall turn the heart of the fathers to the children" },
      [ matt, 1 ] => { 1 => "The book of the generation of Jesus Christ", 2 => "Abraham begat Isaac" }
    }.each do |(book, chapter), verses|
      verses.each { |num, text| Verse.create!(translation: @kjv, book: book, chapter: chapter, verse_number: num, text: text) }
    end
    @study = @user.studies.create!(name: "Sunday", pane_count: 1)
    @study.panes.first.update!(reference: "Matthew 1:1", translation: @kjv)
  end

  teardown do
    go_online
    clear_offline_data
  end

  test "console: Prev on Matthew 1:1 goes back to Malachi 4:6 right after entering preach" do
    start_preaching
    send_keys :arrow_left
    assert_current "Malachi", 4, 6
    send_keys :arrow_right
    assert_current "Matthew", 1, 1
  end

  test "console: Prev on Exodus 1:1 → Genesis 50:26 from the toolbar, with the Bible on the device" do
    start_preaching
    library_live("Exodus 1:1")
    assert_current "Exodus", 1, 1
    go_offline
    find(".ps-preach-tool[data-action~='presentation#prev']").click
    assert_current "Genesis", 50, 26
    find(".ps-preach-tool[data-action~='presentation#next']").click
    assert_current "Exodus", 1, 1
  end

  test "console verse list: ↑ on Matthew 1:1 turns to Malachi 4, Enter previews 4:6" do
    start_preaching
    box = find(".cx-find-input")
    box.set("Matthew 1")
    assert_selector ".ps-verse-list .ttl", text: /Matthew 1/
    box.send_keys(:down)
    assert_equal "1", page.evaluate_script("document.activeElement.closest('.vrow')?.dataset.num")
    page.send_keys(:up)
    assert_selector ".ps-verse-list .ttl", text: /Malachi 4/
    assert_equal "6", page.evaluate_script("document.activeElement.closest('.vrow')?.dataset.num")
    page.send_keys(:enter)
    assert_selector "[data-preview-target='previewLabel']", text: "Malachi 4:6"
    assert_current "Matthew", 1, 1 # Preview only: the screen didn't move
  end

  test "Prev on Genesis 1:1 stays put" do
    start_preaching
    library_live("Genesis 1:1")
    assert_current "Genesis", 1, 1
    send_keys :arrow_left
    assert_selector ".ps-preach-toast", text: /first verse of the bible/i
    assert_current "Genesis", 1, 1
  end

  test "focus view: Prev pressed while the single verse is still opening its chapter isn't lost" do
    visit root_path
    page.execute_script("localStorage.setItem('scriptorium.tourDone', '1')")
    fill_in "reference", with: "Matthew 1:1"
    click_on "Read"
    assert_selector ".ps-pane .ps-verse"
    prefer_focus_view
    find(".ui-appbar button[data-action~='presentation#start']").click
    assert_selector ".ps-root.is-preaching"
    send_keys :arrow_left # at once, while "Matthew 1:1" is still being swapped for Matthew 1
    assert_current "Malachi", 4, 6
    send_keys :page_down
    assert_current "Matthew", 1, 1
  end

  test "a part-chapter pane steps into the rest of its chapter, then on across the book" do
    @study.panes.first.update!(reference: "Exodus 1:2")
    start_preaching
    assert_current "Exodus", 1, 2
    find(".ps-preach-tool[data-action~='presentation#prev']").click
    assert_current "Exodus", 1, 1
    find(".ps-preach-tool[data-action~='presentation#prev']").click
    assert_current "Genesis", 50, 26
  end

  test "a chapter missing from the pane's translation keeps the verse on screen" do
    Verse.joins(:book).where(books: { osis_code: "Mal" }).delete_all
    start_preaching
    library_live("Matthew 1:1")
    assert_current "Matthew", 1, 1
    send_keys :arrow_left
    assert_selector ".ps-preach-toast", text: /isn't in this translation/i
    assert_current "Matthew", 1, 1
  end

  private

  def assert_current(book, chapter, verse)
    assert_selector ".ps-pane.is-presented .ps-verse.is-preach-current[data-chapter='#{chapter}'][data-verse-num='#{verse}']"
    assert_selector ".ps-pane.is-presented .rd-book", text: book, visible: :all
  end

  def library_live(reference)
    box = find("[data-console-library-target='input']")
    box.set(reference)
    assert_selector "[data-console-library-target='hint']", text: /Enter to preview/i
    box.send_keys([ :shift, :enter ])
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
    mark_console_tour_seen
    find(".ui-appbar button[data-action~='presentation#start']").click
    assert_selector ".ps-root.is-preaching.is-console"
    assert_selector ".ps-preach-offline[data-state='ready']", wait: 20
  end

  def send_keys(*keys)
    find("body").send_keys(*keys)
  end
end
