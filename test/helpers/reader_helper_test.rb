require "test_helper"

class ReaderHelperTest < ActionView::TestCase
  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    @matt = Book.create!(osis_code: "Matt", name: "Matthew", testament: :new, position: 40, chapter_count: 28)
    (16..18).each { |v| Verse.create!(translation: @kjv, book: @john, chapter: 3, verse_number: v, text: "t") }
    (5..7).each { |c| Verse.create!(translation: @kjv, book: @matt, chapter: c, verse_number: 1, text: "t") }
  end

  def content_for_ref(reference)
    Pane.new(reference:, translation: @kjv).content
  end

  test "passage_label names chapters and verse ranges the way a Bible app does" do
    assert_equal "John 3", passage_label(content_for_ref("John 3"))
    assert_equal "John 3:16", passage_label(content_for_ref("Jn 3:16"))
    assert_equal "John 3:16–18", passage_label(content_for_ref("John 3:16-18"))
    assert_equal "Matthew 5–7", passage_label(content_for_ref("Matt 5-7"))
    assert_nil passage_label(content_for_ref("Nowhere 9"))
  end

  test "chapter_heading splits the book from a plain chapter number" do
    assert_equal [ "John", "3" ], chapter_heading(content_for_ref("John 3:16"))
    assert_equal [ "Matthew", "5–7" ], chapter_heading(content_for_ref("Matt 5-7"))
  end

  test "icons are inline, decorative unless labelled" do
    svg = icon(:search)
    assert_includes svg, %(aria-hidden="true")
    assert_includes svg, "currentColor"
    assert_includes icon(:x, label: "Close"), %(aria-label="Close")
    assert_raises(KeyError) { icon(:nope) }
  end

  test "books are grouped by testament with search keys" do
    groups = testament_books
    assert_equal 39, groups[:old].size
    assert_equal 27, groups[:new].size
    keys = book_search_keys(groups[:new].find { |b| b.osis == "1Cor" })
    assert_includes keys.split, "1corinthians"
    assert_includes keys.split, "1cor"
  end
end
