require "test_helper"

class ReferenceParserTest < ActiveSupport::TestCase
  def parse(input) = ReferenceParser.call(input)

  # ---- brief-mandated cases ----

  test "Jn 3:16 -> John 3:16" do
    r = parse("Jn 3:16")
    assert r.valid?
    assert_equal "John", r.osis
    assert_equal 3, r.chapter
    assert_equal 16, r.verse_start
    assert_equal 16, r.verse_end
  end

  test "jn 3 -> whole chapter John 3" do
    r = parse("jn 3")
    assert r.valid?
    assert_equal "John", r.osis
    assert_equal 3, r.chapter
    assert_nil r.verse_start
    assert r.whole_chapter?
  end

  test "John 3:16-18 -> verse range" do
    r = parse("John 3:16-18")
    assert r.valid?
    assert_equal 16, r.verse_start
    assert_equal 18, r.verse_end
  end

  test "1 Cor 1:1 -> 1Cor 1:1" do
    r = parse("1 Cor 1:1")
    assert r.valid?
    assert_equal "1Cor", r.osis
    assert_equal 1, r.chapter
    assert_equal 1, r.verse_start
  end

  test "1cor1:1 (no spaces) -> 1Cor 1:1" do
    r = parse("1cor1:1")
    assert r.valid?
    assert_equal "1Cor", r.osis
    assert_equal 1, r.chapter
    assert_equal 1, r.verse_start
  end

  test "1 Cor 13 -> whole chapter" do
    r = parse("1 Cor 13")
    assert r.valid?
    assert_equal "1Cor", r.osis
    assert_equal 13, r.chapter
    assert r.whole_chapter?
  end

  test "Song 2:1 -> Song of Solomon" do
    r = parse("Song 2:1")
    assert r.valid?
    assert_equal "Song", r.osis
    assert_equal 2, r.chapter
    assert_equal 1, r.verse_start
  end

  test "Psalm 23 and Ps 23 resolve identically" do
    a = parse("Psalm 23")
    b = parse("Ps 23")
    assert a.valid? && b.valid?
    assert_equal "Ps", a.osis
    assert_equal a.osis, b.osis
    assert_equal 23, a.chapter
  end

  test "romans 5:1 lowercase" do
    r = parse("romans 5:1")
    assert r.valid?
    assert_equal "Rom", r.osis
    assert_equal 5, r.chapter
    assert_equal 1, r.verse_start
  end

  # ---- edge cases ----

  test "blank and gibberish are invalid" do
    refute parse("").valid?
    refute parse("   ").valid?
    refute parse("nonsense 4:5").valid?
    refute parse(nil).valid?
  end

  test "chapter beyond the book's range is invalid" do
    refute parse("John 99").valid?     # John has 21 chapters
    refute parse("Ps 151").valid?      # Psalms has 150
  end

  test "bare multi-chapter book name is invalid" do
    refute parse("Romans").valid?
  end

  test "single-chapter book without chapter defaults to chapter 1" do
    r = parse("Obadiah")
    assert r.valid?
    assert_equal "Obad", r.osis
    assert_equal 1, r.chapter
    r2 = parse("Jude")
    assert r2.valid?
    assert_equal "Jude", r2.osis
    assert_equal 1, r2.chapter
  end

  test "reversed verse range is invalid" do
    refute parse("John 3:18-16").valid?
  end

  test "ordinal words and en-dash ranges" do
    assert_equal "1John", parse("First John 4:7").osis
    assert_equal "2Tim", parse("2nd Tim 3:16").osis
    r = parse("John 3:16–18") # en-dash
    assert r.valid?
    assert_equal 18, r.verse_end
  end

  test "trailing/leading whitespace and dotted abbreviations" do
    assert_equal "Gen", parse("  gen. 1:1 ").osis
    assert_equal "Phil", parse("Phil. 4:13").osis
  end

  test "label round-trips" do
    assert_equal "John 3:16", parse("Jn 3:16").label
    assert_equal "John 3:16-18", parse("John 3:16-18").label
    assert_equal "1 Corinthians 13", parse("1 Cor 13").label
  end
end
