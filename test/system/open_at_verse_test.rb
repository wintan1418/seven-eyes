require "application_system_test_case"

# Like a KJV Bible app (the founder's benchmark, Nov 2026): a search result
# opens the WHOLE chapter scrolled to the verse, the verse marked; the phone
# reader reads verse per line under one compact bar, with previous / next at
# the end of the chapter instead of arrows over the text.
class OpenAtVerseTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 412, 915 ], options: { name: :selenium_pixel_open_at_verse } do |opts|
    opts.add_emulation(device_name: "Pixel 7")
    path = begin
      Selenium::WebDriver::SeleniumManager.binary_paths("--browser", "chrome")["browser_path"]
    rescue StandardError
      nil
    end
    opts.binary = path if path.present?
  end

  setup do
    kjv = Translation.create!(code: "KJV", name: "King James Version")
    @deut = Book.create!(osis_code: "Deut", name: "Deuteronomy", testament: :old, position: 5, chapter_count: 34)
    job = Book.create!(osis_code: "Job", name: "Job", testament: :old, position: 18, chapter_count: 42)
    (1..40).each do |v|
      text = case v
      when 2 then "My doctrine shall drop as the rain, my speech shall distil as the dew"
      when 30 then "How should one chase a thousand, and two put ten thousand to flight"
      else "Verse #{v} of the song of Moses, long enough to wrap onto a second line on a phone."
      end
      Verse.create!(translation: kjv, book: @deut, chapter: 32, verse_number: v, text:)
    end
    Verse.create!(translation: kjv, book: @deut, chapter: 31, verse_number: 1, text: "And Moses went and spake these words")
    Verse.create!(translation: kjv, book: @deut, chapter: 33, verse_number: 1, text: "And this is the blessing, wherewith Moses blessed")
    Verse.create!(translation: kjv, book: job, chapter: 38, verse_number: 28, text: "Hath the rain a father? or who hath begotten the drops of dew?")
  end

  test "a search-sheet result opens the whole chapter at the verse, marked; next chapter goes on from there" do
    open_reader("Deuteronomy 31")
    find(".ui-appbar [data-action~='search#open']").click
    assert_selector ".ps-search-drawer.is-open"
    sleep 0.5 # the sheet slides up
    within(".ps-search-panel") do
      find("input[name=q]").fill_in(with: "dew rain")
      find("button[type=submit]", text: "Search").click
      assert_selector ".sr-summary", text: "Showing 2 verses containing dew and rain"
      assert_equal [ "Deuteronomy 32:2", "Job 38:28" ], all(".sr-hit .sr-ref").map(&:text)
      assert_selector ".sr-hit mark", text: "dew"
      find(".sr-open", text: "Deuteronomy 32:2").click
    end

    assert_no_selector ".ps-search-drawer.is-open"
    assert_selector ".ps-verse[data-verse-num]", count: 40 # the whole chapter, not verse 2 alone
    assert_selector ".ps-verse.is-focus", count: 1
    assert_selector ".ps-verse.is-focus[data-verse-num='2']"
    assert_selector ".ui-appbar [data-reader-header-target='reference']", text: "Deuteronomy 32"
    assert_selector ".ps-verse.is-focus:not(.is-focus-flash)", wait: 6 # the wash fades, the mark stays

    page.execute_script("document.querySelector('.ps-verses').scrollTop = 1e6")
    find(".rd-pager-btn.is-next").click
    assert_selector ".ps-verse-text", text: "And this is the blessing"
    assert_selector ".ui-appbar [data-reader-header-target='reference']", text: "Deuteronomy 33"
  end

  test "a verse deep in the chapter is scrolled to the middle; a range marks every verse" do
    visit read_path(ref: "Deuteronomy 32:30-31")
    assert_selector ".ps-verse.is-focus", count: 2
    assert_selector ".ps-verse.is-focus[data-verse-num='30']"
    sleep 0.3
    centre = page.evaluate_script(<<~JS)
      (() => {
        const box = document.querySelector(".ps-verses").getBoundingClientRect()
        const a = document.querySelector(".ps-verse[data-verse-num='30']").getBoundingClientRect()
        const b = document.querySelector(".ps-verse[data-verse-num='31']").getBoundingClientRect()
        return Math.abs((a.top + b.bottom) / 2 - (box.top + box.bottom) / 2) / box.height
      })()
    JS
    assert_operator centre, :<, 0.1, "the marked verses sit in the middle of the reader"
    assert_equal "", page.evaluate_script("location.search"), "?verse= is dropped once used (a reload reads plainly)"
  end

  test "the /search page: every word first, matched words marked, tap opens the chapter; recent searches stay" do
    visit search_path
    page.execute_script("localStorage.setItem('scriptorium.tourDone', '1')")
    assert_selector ".sr-empty"
    find("input[name=q]").fill_in(with: "dew rain")
    click_on "Search"
    assert_selector ".sr-summary", text: "Showing 2 verses containing dew and rain · KJV"
    assert_equal({ "q" => "dew rain", "in" => "all", "t" => "KJV" }, Rack::Utils.parse_query(URI(current_url).query))
    assert_selector ".sr-hit .sr-text mark", text: "rain"
    find(".sr-open", text: "Deuteronomy 32:2").click

    assert_selector ".ps-verse.is-focus[data-verse-num='2']"
    assert_selector ".ps-verse[data-verse-num]", count: 40

    visit search_path
    assert_selector ".sr-recent:not([hidden]) .sr-recent-item", text: "dew rain"
    find(".sr-recent-item", text: "dew rain").click
    assert_selector ".sr-hit", minimum: 2
  end

  test "the phone reader: one compact bar, verse per line, tools beside the chapter line, no arrows over the text" do
    open_reader("Deuteronomy 32")
    assert_selector ".ps-root.is-verse-lines"
    assert_no_selector ".ui-appbar .ui-brand", visible: true
    assert_selector ".ui-appbar .ui-chip.is-passage", visible: true
    assert_selector ".ui-appbar [data-action~='search#open']", visible: true
    assert_selector ".ui-appbar .ui-appbar-aa", visible: true
    assert_no_selector ".rd-chapter-nav .rd-fab", visible: true

    size = page.evaluate_script("parseFloat(getComputedStyle(document.querySelector('.ps-verse-text')).fontSize)")
    assert_operator size, :<=, 20, "reading size like a Bible app (was 26px)"
    verse1 = rect(".ps-verse[data-verse-num='1']")
    verse2 = rect(".ps-verse[data-verse-num='2']")
    assert_operator verse2["top"], :>=, verse1["bottom"] - 1, "each verse starts on its own line"
    head = rect(".rd-chapter-head")
    tools = rect(".rd-chapter-tools")
    assert_operator (tools["top"] - head["top"]).abs, :<, 12, "listen / focus / notes sit on the chapter line"

    # Paragraphs stay a choice in Reading settings.
    find(".ui-appbar .ui-appbar-aa").click
    assert_selector ".ui-settings-sheet.is-open"
    sleep 0.5 # the sheet slides up
    find(".ui-settings-sheet [data-action~='verse-lines#toggle']").click
    assert_selector ".ps-root.is-verse-paragraphs"
    assert_equal "0", page.evaluate_script("localStorage.getItem('ps:verse-lines')")
  end

  private

  def open_reader(reference)
    visit read_path(ref: reference)
    page.execute_script("localStorage.setItem('scriptorium.tourDone', '1')")
    visit current_path
    assert_selector ".ps-verse", minimum: 1
    wait_for_reader_js
  end

  def rect(selector) = page.evaluate_script("document.querySelector(#{selector.to_json}).getBoundingClientRect().toJSON()")
end
