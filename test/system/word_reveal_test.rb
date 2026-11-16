require "application_system_test_case"

# Hold a word, see the original: long-press (or double-click) a word in the
# reader and its Hebrew or Greek rises under it — in any translation, since
# the word is matched through the verse's Strong's-tagged KJV tokens.
class WordRevealTest < ApplicationSystemTestCase
  KJV_TEXT = "For God so loved the world, that he gave his only begotten Son."
  WEB_TEXT = "For God so loved the world, that he gave his one and only Son."

  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @web = Translation.create!(code: "WEB", name: "World English Bible")
    john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    tokens = [ [ "For", "G1063" ], [ " God", "G2316" ], [ " so", "G3779" ], [ " loved", "G25" ], [ " the world", "G2889" ],
               [ ", that", "G5620" ], [ " he gave", "G1325" ], [ " his", "G846" ], [ " only begotten", "G3439" ],
               [ " Son", "G5207" ], [ "." ] ].map { |w, s| s ? { "w" => w, "s" => s } : { "w" => w } }
    Verse.create!(translation: @kjv, book: john, chapter: 3, verse_number: 16, text: KJV_TEXT, tokens:)
    Verse.create!(translation: @web, book: john, chapter: 3, verse_number: 16, text: WEB_TEXT)
    LexiconEntry.create!(strongs: "G25", language: "greek", lemma: "ἀγαπάω", translit: "agapáō",
                         definition: "to love (in a social or moral sense)", kjv_def: "(be-)love(-ed)")
  end

  test "select “loved” in the KJV: ἀγαπάω rises under it, and Word study opens the drawer" do
    open_reader("John 3:16", "KJV")
    select_word("loved")
    card = find(".wr-card.is-in[data-strongs='G25']", wait: 5)
    assert_includes card.text, "ἀγαπάω"
    assert_includes card.text, "agapáō"
    assert_includes card.text, "GREEK"
    assert_includes card.text, "“loved”"

    # It sits under the word, inside the window.
    word = page.evaluate_script("window.getSelection().getRangeAt(0).getBoundingClientRect().toJSON()")
    box = page.evaluate_script("document.querySelector('.wr-card').getBoundingClientRect().toJSON()")
    assert_operator box["top"], :>, word["bottom"]
    assert_operator box["left"], :>=, 0
    assert_operator box["right"], :<=, page.evaluate_script("window.innerWidth")

    card.find(".wr-more").click
    assert_no_selector ".wr-card"
    assert_selector ".ps-lexicon-host.is-open, [data-lexicon-target='host'].is-open", visible: :all, wait: 5
  end

  test "any translation: “loved” in the WEB finds the KJV’s Greek; a plain word shows nothing" do
    open_reader("John 3:16", "WEB")
    select_word("the")
    sleep 0.8
    assert_no_selector ".wr-card"

    select_word("loved")
    assert_selector ".wr-card.is-in[data-strongs='G25']", text: "ἀγαπάω", wait: 5

    # Clearing the selection puts it away.
    page.execute_script("window.getSelection().removeAllRanges()")
    assert_no_selector ".wr-card", wait: 3
  end

  test "Aa → Original words off: selecting a word shows nothing, and it is remembered" do
    open_reader("John 3:16", "KJV")
    find(".ui-appbar [data-sheets-id-param='settings']", match: :first).click
    find("[data-action~='word-reveal#toggle']").click
    assert_selector ".ps-root.no-word-reveal"
    assert_selector "[data-action~='word-reveal#toggle'][aria-pressed='false']"
    visit current_url
    assert_selector ".ps-root.no-word-reveal"
    select_word("loved")
    sleep 0.8
    assert_no_selector ".wr-card"
    page.execute_script("localStorage.removeItem('ps:word-reveal')")
  end

  private

  def open_reader(reference, translation)
    visit read_path(ref: reference, t: translation)
    page.execute_script("localStorage.setItem('scriptorium.tourDone', '1')")
    visit current_url
    assert_selector ".ps-verse[data-verse-num='16']"
    wait_for_reader_js
  end

  # What a long-press or a double-click does: select that one word.
  def select_word(word)
    page.execute_script(<<~JS, word)
      const want = arguments[0]
      const box = document.querySelector(".ps-verse[data-verse-num='16'] .ps-verse-text")
      const walker = document.createTreeWalker(box, NodeFilter.SHOW_TEXT)
      const re = new RegExp("\\\\b" + want + "\\\\b")
      for (let n = walker.nextNode(); n; n = walker.nextNode()) {
        const m = re.exec(n.data)
        if (!m) continue
        const range = document.createRange()
        range.setStart(n, m.index)
        range.setEnd(n, m.index + want.length)
        const sel = window.getSelection()
        sel.removeAllRanges()
        sel.addRange(range)
        break
      }
    JS
  end
end
