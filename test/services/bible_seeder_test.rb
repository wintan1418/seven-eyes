require "test_helper"

class BibleSeederTest < ActiveSupport::TestCase
  setup do
    @gen = Book.create!(osis_code: "Gen", name: "Genesis", testament: :old, position: 1, chapter_count: 50)
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    @json = file_fixture("helloao_mini.json").read
  end

  def seeder(code = "BSB", force: false, json: @json)
    BibleSeeder.new(code, force:, fetcher: -> { json })
  end

  test "seeds verses from the source without any HTTP and stamps verse_count" do
    t = seeder.run
    assert_equal "BSB", t.code
    assert_equal 3, t.verses.count, "blank verse and non-canon book are skipped"
    assert_equal 3, t.verse_count
    assert_equal "For God so loved the world, that He gave His one and only Son.",
                 t.verses.find_by(book: @john, chapter: 3, verse_number: 16).text
  end

  test "verse_text joins parts without a space before closing punctuation" do
    assert_equal "you will strike his heel.”", BibleSeeder.verse_text([ "you will strike his heel.", "”" ])
    assert_equal "Jesus said, “Who touched me?” And they wondered.",
                 BibleSeeder.verse_text([ "Jesus said,", { "text" => "“Who touched me?”" }, { "noteId" => 4 },
                                          "¶ And  they   wondered." ])
    assert_equal "said, ‘Take up your mat and walk.’”",
                 BibleSeeder.verse_text([ "said,", { "text" => "‘Take up your mat and walk.’" }, "”" ])
  end

  test "verse_text strips LSV || poetry markers" do
    assert_equal "For sevenfold is required for Cain, And for Lamech seventy-sevenfold.”",
                 BibleSeeder.verse_text([ "For sevenfold is required for Cain, || And for Lamech seventy-sevenfold.”" ])
  end

  test "a failed download creates no Translation row" do
    broken = BibleSeeder.new("ASV", fetcher: -> { raise SocketError, "offline" })
    assert_raises(SocketError) { broken.run }
    assert_nil Translation.find_by(code: "ASV")

    assert_raises(JSON::ParserError) { seeder("ASV", json: "<html>502</html>").run }
    assert_nil Translation.find_by(code: "ASV")
  end

  test "an incomplete translation is re-seeded on the next run" do
    t = Translation.create!(code: "BSB", name: "Berean Standard Bible")
    Verse.create!(translation: t, book: @gen, chapter: 1, verse_number: 1, text: "In the beginning")
    seeder.run
    assert_equal 4, t.reload.verses.count
    assert_equal 4, t.verse_count
  end

  test "a complete translation is skipped unless forced" do
    t = Translation.create!(code: "BSB", name: "Berean Standard Bible")
    called = false
    stub = BibleSeeder.new("BSB", fetcher: -> { called = true; @json })
    now = Time.current
    rows = (1..Translation::COMPLETE_VERSE_COUNT).map do |i|
      { translation_id: t.id, book_id: @gen.id, chapter: 1 + (i / 1000), verse_number: 1 + (i % 1000),
        text: "v", created_at: now, updated_at: now }
    end
    Verse.insert_all(rows)
    stub.run
    refute called, "a complete translation must not be downloaded again"
    assert_equal Translation::COMPLETE_VERSE_COUNT, t.reload.verse_count, "the cached count is refreshed"
  end

  test "FORCE re-seed upserts in place: verse ids survive and highlights keep their verse" do
    t = seeder.run
    verse = t.verses.find_by(book: @john, chapter: 3, verse_number: 16)
    verse.update_columns(text: "stale text")
    highlight = Highlight.create!(user: users(:one), verse:, char_start: 0, char_end: 3, color: 0)

    seeder(force: true).run

    reloaded = Verse.find(verse.id)
    assert_equal "For God so loved the world, that He gave His one and only Son.", reloaded.text
    assert_equal verse.id, highlight.reload.verse_id
    assert_equal 3, t.reload.verses.count
  end

  test "restricted translations are never seeded by default" do
    refute_includes BibleSeeder::MVP_CODES, "NET"
    refute_includes BibleSeeder::ALL_CODES, "NET"
    BibleSeeder.seed!(%w[NET])
    assert_nil Translation.find_by(code: "NET")
  end

  test "verify reports verse count, books and missing chapters" do
    seeder.run
    row = BibleSeeder.verify.find { |r| r.code == "BSB" }
    assert_equal 3, row.verse_count
    assert_equal 2, row.books
    assert_includes row.missing_chapters, "Gen 1"
    assert_includes row.missing_chapters, "John 21"
    refute_includes row.missing_chapters, "John 3"
    assert_includes row.missing_books, "Exod"
    refute row.complete?
  end
end
