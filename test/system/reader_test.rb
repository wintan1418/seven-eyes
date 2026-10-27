require "application_system_test_case"

# The everyday reader: one passage, a passage picker, a version picker and
# prev/next chapter — the YouVersion-style flow.
class ReaderTest < ApplicationSystemTestCase
  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @bsb = Translation.create!(code: "BSB", name: "Berean Standard Bible")
    john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    rom = Book.create!(osis_code: "Rom", name: "Romans", testament: :new, position: 45, chapter_count: 16)
    { 3 => 16, 4 => 1 }.each do |chapter, verse|
      Verse.create!(translation: @kjv, book: john, chapter:, verse_number: verse, text: "KJV John #{chapter}:#{verse}")
      Verse.create!(translation: @bsb, book: john, chapter:, verse_number: verse, text: "BSB John #{chapter}:#{verse}")
    end
    Verse.create!(translation: @kjv, book: john, chapter: 3, verse_number: 17, text: "KJV John 3:17")
    Verse.create!(translation: @kjv, book: rom, chapter: 8, verse_number: 28, text: "And we know that all things work together")
  end

  test "quick-open lands on a single pane; next chapter and the version sheet work" do
    open_reader("John 3")
    assert_selector ".ps-workspace .ps-pane", count: 1
    assert_selector ".ui-appbar [data-reader-header-target='reference']", text: "John 3"

    find(".rd-chapter-nav .rd-fab.next").click
    assert_selector ".ps-verse-text", text: "KJV John 4:1"
    assert_selector ".ui-appbar [data-reader-header-target='reference']", text: "John 4"

    find(".ui-appbar [data-sheets-id-param='translation']").click
    within(".ui-translation-sheet") { find(".ui-option", text: "BSB").click }
    assert_selector ".ps-verse-text", text: "BSB John 4:1"
    assert_selector ".ui-appbar [data-reader-header-target='translation']", text: "BSB"
    assert_no_selector ".ui-translation-sheet.is-open"
  end

  test "the passage sheet: filter books, pick a chapter, or type a reference" do
    open_reader("John 3")
    find(".ui-appbar [data-sheets-id-param='passage']").click
    within(".ui-passage-sheet") do
      find("input[type=search]").fill_in(with: "rom")
      assert_selector ".ui-book:not([hidden])", text: "Romans"
      assert_no_selector ".ui-book", text: "John", visible: true
      find(".ui-book", text: "Romans").click
      find(".ui-chapter", text: /\A8\z/).click
    end
    assert_selector ".ps-verse-text", text: "all things work together"

    find("body").send_keys([ :control, "k" ])
    assert_selector ".ui-passage-sheet.is-open"
    find(".ui-passage-sheet input[type=search]").fill_in(with: "jn 3:16")
    find(".ui-passage-sheet input[type=search]").send_keys(:enter)
    assert_selector ".ps-verse", count: 1
    assert_selector ".ps-verse-text", text: "KJV John 3:16"
  end

  test "Compare opens a second pane in another version, Done closes it" do
    open_reader("John 3:16")
    find(".ui-appbar [data-shot='compare']").click
    assert_selector ".ps-workspace .ps-pane", count: 2
    assert_selector ".ps-pane .ps-verse-text", text: "BSB John 3:16"
    find(".ui-comparebar .is-close").click
    assert_selector ".ps-workspace .ps-pane", count: 1
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
