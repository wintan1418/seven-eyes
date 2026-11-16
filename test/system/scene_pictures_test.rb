require "application_system_test_case"

# Scene pictures: a faint Doré engraving behind the text of what is happening
# in the passage — Cain and Abel in Genesis 4, the garden in Genesis 3 —
# changing as the reader scrolls past the verse a plate shows.
class ScenePicturesTest < ApplicationSystemTestCase
  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    gen = Book.create!(osis_code: "Gen", name: "Genesis", testament: :old, position: 1, chapter_count: 50)
    phlm = Book.create!(osis_code: "Phlm", name: "Philemon", testament: :new, position: 57, chapter_count: 1)
    (1..26).each { |v| Verse.create!(translation: @kjv, book: gen, chapter: 4, verse_number: v, text: "Genesis four verse #{v}. " * 6) }
    Verse.create!(translation: @kjv, book: phlm, chapter: 1, verse_number: 1, text: "Paul, a prisoner of Jesus Christ")
    @gen4 = ScriptureScenes.all.select { |s| s.osis == "Gen" && s.chapter == 4 }
  end

  test "Genesis 4 shows its plate behind the text; Philemon has none; the switch turns it off" do
    skip "no Genesis 4 plate in config/scripture_scenes.yml" if @gen4.empty?
    open_reader("Genesis 4")
    assert_selector ".ps-pane > .rd-scene.is-on img.is-shown[src='#{@gen4.first.path}']", visible: :all, wait: 5

    # Scroll to the end of the chapter: the plate for the last scene in it.
    page.execute_script("document.querySelector('.ps-verses').scrollTop = 1e6")
    assert_selector ".ps-pane > .rd-scene.is-on img.is-shown[src='#{@gen4.last.path}']", visible: :all, wait: 5

    # The words stay above the picture.
    z = page.evaluate_script("[getComputedStyle(document.querySelector('.rd-scene')).zIndex, getComputedStyle(document.querySelector('.ps-verses')).zIndex]")
    assert_equal [ "0", "1" ], z

    # Reading settings → Scene pictures off: gone, and remembered.
    find(".ui-appbar [data-sheets-id-param='settings']", match: :first).click
    find("[data-action~='scene#toggle']").click
    assert_selector ".ps-root.no-scenes"
    assert_selector "[data-action~='scene#toggle'][aria-pressed='false']"
    assert_no_selector ".rd-scene", visible: true
    visit current_url
    assert_selector ".ps-root.no-scenes"
    page.execute_script("localStorage.removeItem('ps:scenes')")
  end

  test "a book with no plate stays plain" do
    open_reader("Philemon 1")
    assert_selector ".ps-verse"
    assert_no_selector ".rd-scene.is-on", visible: :all
  end

  private

  def open_reader(reference)
    visit root_path
    page.execute_script("localStorage.setItem('scriptorium.tourDone', '1')")
    fill_in "reference", with: reference
    click_on "Read"
    assert_selector ".ps-verse"
  end
end
