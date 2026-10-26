require "test_helper"

class ReferenceParserTest < ActiveSupport::TestCase
  def parse(input) = ReferenceParser.call(input)
  def loc(r) = [ r.chapter, r.verse_start, r.verse_end ]

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

  # ---- a bare book name opens the book ----

  test "bare multi-chapter book name opens chapter 1" do
    %w[Philippians Romans genesis Rev].each do |q|
      r = parse(q)
      assert r.valid?, "#{q} should parse"
      assert_equal 1, r.chapter
      assert r.whole_chapter?
    end
    assert_equal "Phil", parse("Philippians").osis
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

  test "single-chapter book with a bare number means a verse (Jude 3 -> Jude 1:3)" do
    r = parse("jude 3")
    assert r.valid?
    assert_equal "Jude", r.osis
    assert_equal 1, r.chapter
    assert_equal 3, r.verse_start
    assert_equal "Jude 1:3", r.label

    r = parse("Philemon 1:6")
    assert_equal 6, r.verse_start

    r = parse("Jude 3-5")
    assert_equal [ 1, 3, 5 ], [ r.chapter, r.verse_start, r.verse_end ]
  end

  # ---- misspellings and loose typing ----

  test "common misspellings resolve to the intended book" do
    {
      "phillipians 4:13" => "Phil",
      "philipians 4" => "Phil",
      "Phillipians" => "Phil",
      "mathew 5" => "Matt",
      "isiah 53" => "Isa",
      "galations 5" => "Gal",
      "collosians 3" => "Col",
      "revelations 1" => "Rev",
      "hebrew 11" => "Heb",
      "ephesian 2" => "Eph",
      "duet 6" => "Deut",
      "psalms 23" => "Ps",
      "corinthians 13" => nil, # genuinely ambiguous between 1 and 2 Corinthians
      "philip 4" => "Phil",     # unique prefix of a full name
      "phile 1" => "Phlm",
      "gene 1" => "Gen",
      "thes 1" => nil           # ambiguous prefix (1/2 Thessalonians)
    }.each do |input, osis|
      r = parse(input)
      if osis
        assert r.valid?, "#{input.inspect} should parse"
        assert_equal osis, r.osis, "#{input.inspect} resolved to the wrong book"
      else
        refute r.valid?, "#{input.inspect} should not guess a book"
      end
    end
  end

  test "Roman numeral book prefixes" do
    assert_equal "1Cor", parse("I Corinthians 13").osis
    assert_equal "2Kgs", parse("II Kings 2").osis
    assert_equal "3John", parse("III John").osis
    assert_equal "1John", parse("i john 4:7").osis
    # a leading 'i' that is part of a name is untouched
    assert_equal "Isa", parse("isaiah 53").osis
  end

  test "period, comma, and space as chapter/verse separators" do
    assert_equal [ 3, 16, 16 ], loc(parse("Jn 3.16"))
    assert_equal [ 3, 16, 16 ], loc(parse("john 3 16"))
    assert_equal [ 3, 16, 18 ], loc(parse("john 3,16-18"))
    assert_equal [ 3, 16, 16 ], loc(parse("John 3 v 16"))
    assert_equal [ 3, 16, 16 ], loc(parse("John 3 vs 16"))
    assert_equal [ 3, 16, 16 ], loc(parse("John chapter 3 verse 16"))
    assert_equal [ 3, 16, 18 ], loc(parse("John 3:16 - 18"))
  end

  test "reversed verse range is swapped into order" do
    r = parse("John 3:18-16")
    assert r.valid?
    assert_equal 16, r.verse_start
    assert_equal 18, r.verse_end
  end

  # ---- edge cases ----

  test "blank and gibberish are invalid with a reason" do
    refute parse("").valid?
    assert_equal :blank, parse("").error
    refute parse("   ").valid?
    refute parse(nil).valid?
    r = parse("nonsense 4:5")
    refute r.valid?
    assert_equal :unknown_book, r.error
    refute parse("blorbity 99").valid?
    refute parse("xylophone").valid?
    refute parse("12345").valid?
  end

  test "chapter beyond the book's range is invalid but names the book" do
    r = parse("John 99") # John has 21 chapters
    refute r.valid?
    assert_equal :bad_chapter, r.error
    assert_equal "John", r.osis
    assert_equal "John", r.book_name
    assert_equal 21, r.chapter_count

    r = parse("Ps 151") # Psalms has 150
    refute r.valid?
    assert_equal :bad_chapter, r.error
    assert_equal 150, r.chapter_count
  end

  test "zero chapter or verse is invalid" do
    refute parse("John 0").valid?
    refute parse("John 3:0").valid?
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
    assert_equal "Phil", parse("Phil 4:13.").osis
  end

  test "tolerates colon as book/chapter separator" do
    assert_equal "Jer",  parse("jeremiah:3").osis
    assert_equal 3,      parse("jeremiah:3").chapter
    assert_equal "John", parse("john:3:16").osis
    assert_equal 16,     parse("john:3:16").verse_start
    # but a colon between digits (chapter:verse) is still respected
    assert_equal "John", parse("John 3:16").osis
    assert_equal 16,     parse("John 3:16").verse_start
  end

  test "label round-trips" do
    assert_equal "John 3:16", parse("Jn 3:16").label
    assert_equal "John 3:16-18", parse("John 3:16-18").label
    assert_equal "1 Corinthians 13", parse("1 Cor 13").label
    assert_equal "Philippians 1", parse("Philippians").label
  end

  test "every canonical name and alias resolves to itself" do
    Bible::Canon.all.each do |entry|
      ([ entry.name, entry.osis ] + entry.aliases).each do |token|
        r = parse("#{token} 1")
        assert r.valid?, "#{token.inspect} should parse"
        assert_equal entry.osis, r.osis, "#{token.inspect} resolved to #{r.osis}"
      end
    end
  end
end
