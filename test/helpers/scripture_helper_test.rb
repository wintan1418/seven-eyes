require "test_helper"

class ScriptureHelperTest < ActionView::TestCase
  setup do
    @gen = Book.create!(osis_code: "Gen", name: "Genesis", testament: :old, position: 1, chapter_count: 50)
    @exo = Book.create!(osis_code: "Exod", name: "Exodus", testament: :old, position: 2, chapter_count: 40)
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    @acts = Book.create!(osis_code: "Acts", name: "Acts", testament: :new, position: 44, chapter_count: 28)
  end

  test "neighbor_reference returns the next chapter within a book" do
    assert_equal "John 4", neighbor_reference(@john, 3, :next)
  end

  test "neighbor_reference returns the previous chapter within a book" do
    assert_equal "John 2", neighbor_reference(@john, 3, :prev)
  end

  test "neighbor_reference wraps to the next book at the end of one" do
    assert_equal "Acts 1", neighbor_reference(@john, 21, :next)
  end

  test "neighbor_reference wraps to the previous book at chapter 1" do
    assert_equal "Genesis 50", neighbor_reference(@exo, 1, :prev)
  end

  test "neighbor_reference returns nil at the very start of the canon" do
    assert_nil neighbor_reference(@gen, 1, :prev)
  end

  test "reference_title spans chapters" do
    assert_equal "John III", reference_title(@john, 3)
    assert_equal "John III–IV", reference_title(@john, 3, 4)
    assert_equal "John III", reference_title(@john, 3, 3)
  end

  # ---- notes: stored XSS regression ----

  test "render_notes escapes user HTML but keeps wiki-links working" do
    study = users(:one).studies.create!(name: "S", pane_count: 1)
    html = render_notes("<img src=x onerror=alert(1)> see [[John 3:16]]\n<script>bad()</script>", study:)
    refute_includes html, "<img"
    refute_includes html, "<script>"
    assert_includes html, "&lt;img src=x onerror=alert(1)&gt;"
    assert_includes html, "&lt;script&gt;bad()&lt;/script&gt;"
    assert_includes html, "<a class=\"ps-note-link\""
    assert_includes html, "[[John 3:16]]"
    assert_includes html, "<br />"
  end

  test "render_notes escapes HTML inside an unresolvable wiki-link" do
    study = users(:one).studies.create!(name: "S", pane_count: 1)
    html = render_notes("[[<b onmouseover=x>nope]]", study:)
    refute_includes html, "<b "
  end

  # ---- tokens + highlights render the same visible text ----

  Hl = Struct.new(:id, :char_start, :char_end, :color, :note)

  def kjv_verse(tokens: nil)
    t = Translation.create!(code: "KJV", name: "King James Version")
    Verse.create!(translation: t, book: @john, chapter: 3, verse_number: 16,
                  text: "For God so loved the world", tokens:)
  end

  def text_of(html) = Nokogiri::HTML.fragment(html.to_s).at_css(".ps-verse-text").text

  test "tagged and highlighted renderings show exactly verse.text" do
    tokens = [ { "w" => "For", "s" => "G1063" }, { "w" => "  God", "s" => "G2316" }, { "w" => " so loved the world" } ]
    verse = kjv_verse(tokens:)
    study = users(:one).studies.create!(name: "S", pane_count: 1)

    plain = scripture_verse(verse, study:, book: @john)
    lit = scripture_verse(verse, study:, book: @john, highlights: [ Hl.new(1, 4, 13, "ochre", nil) ])
    assert_equal verse.text, text_of(plain)
    assert_equal verse.text, text_of(lit)

    doc = Nokogiri::HTML.fragment(lit.to_s)
    assert_equal "God so lo", doc.at_css(".hl-ochre").text
    assert doc.css(".ps-word").any? { |w| w["data-strongs"] == "G2316" }, "Strong's words survive highlighting"
  end

  test "tokens that don't spell the verse are not rendered" do
    verse = kjv_verse(tokens: [ { "w" => "undefiled: or, perfect", "s" => "H1" } ])
    study = users(:one).studies.create!(name: "S", pane_count: 1)
    html = scripture_verse(verse, study:, book: @john)
    assert_equal verse.text, text_of(html)
    assert_empty Nokogiri::HTML.fragment(html.to_s).css(".ps-word")
  end

  test "tokens align over typographic variants and stray spaces before punctuation" do
    t = Translation.create!(code: "KJV", name: "King James Version")
    verse = Verse.create!(translation: t, book: @john, chapter: 3, verse_number: 22,
                          text: "into the land of Judæa, his mother’s womb.",
                          tokens: [ { "w" => "into the land", "s" => "G1519" }, { "w" => " of Judaea", "s" => "G2449" },
                                    { "w" => " , his mother's" }, { "w" => " womb", "s" => "G2836" }, { "w" => " ." } ])
    study = users(:one).studies.create!(name: "S", pane_count: 1)
    html = scripture_verse(verse, study:, book: @john)
    assert_equal verse.text, text_of(html)
    words = Nokogiri::HTML.fragment(html.to_s).css(".ps-word").map(&:text)
    assert_equal [ "into the land", " of Judæa", " womb" ], words
  end

  test "link_numbers: false renders a read-only verse with the same contract" do
    verse = kjv_verse(tokens: [ { "w" => "For", "s" => "G1063" }, { "w" => " God so loved the world" } ])
    study = users(:one).studies.create!(name: "S", pane_count: 1)
    doc = Nokogiri::HTML.fragment(scripture_verse(verse, study:, book: @john, dropcap: true, link_numbers: false).to_s)
    assert_nil doc.at_css("a")
    assert_equal "16", doc.at_css("span.ps-vnum").text
    word = doc.at_css(".ps-word")
    assert_nil word["data-href"]
    assert_nil word["data-action"]
    texts = doc.css(".ps-verse-text")
    assert_equal 1, texts.size
    assert_equal "1", texts.first["data-offset-base"]
    assert_equal verse.text[1..], texts.first.text
    assert_equal "ps-dropcap", texts.first.previous_element["class"]
  end

  test "overlapping highlights are clipped, not dropped" do
    text = "For God so loved the world"
    outer = Hl.new(1, 0, 16, "ochre", nil)   # "For God so loved"
    inner = Hl.new(2, 4, 7, "rose", "note")  # "God"
    tail  = Hl.new(3, 11, 26, "sage", nil)   # "loved the world" — overlaps outer
    doc = Nokogiri::HTML.fragment(highlight_text(text, [ outer, inner, tail ]).to_s)

    assert_equal text, doc.text
    ids = doc.css("[data-highlight-id]").map { |n| n["data-highlight-id"] }.uniq.sort
    assert_equal %w[1 2 3], ids, "every highlight keeps a clickable stretch"
    assert_equal "God", doc.at_css(".hl-rose").text
  end

  test "translation_options lists only available translations" do
    Translation.create!(code: "KJV", name: "King James Version")
    Translation.create!(code: "NET", name: "NET Bible")
    Translation.create!(code: "WEB", name: "World English Bible", verse_count: 500)
    html = translation_options(nil)
    assert_includes html, ">KJV<"
    refute_includes html, "NET"
    refute_includes html, "WEB"
  end
end
