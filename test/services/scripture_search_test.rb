require "test_helper"

class ScriptureSearchTest < ActiveSupport::TestCase
  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    gen = Book.create!(osis_code: "Gen", name: "Genesis", testament: :old, position: 1, chapter_count: 50)
    deut = Book.create!(osis_code: "Deut", name: "Deuteronomy", testament: :old, position: 5, chapter_count: 34)
    job = Book.create!(osis_code: "Job", name: "Job", testament: :old, position: 18, chapter_count: 42)
    matt = Book.create!(osis_code: "Matt", name: "Matthew", testament: :new, position: 40, chapter_count: 28)
    # Stored out of Bible order on purpose: results must not depend on it.
    Verse.create!(translation: @kjv, book: job, chapter: 38, verse_number: 28,
                  text: "Hath the rain a father? or who hath begotten the drops of dew?")
    Verse.create!(translation: @kjv, book: gen, chapter: 2, verse_number: 5,
                  text: "for the LORD God had not caused it to rain upon the earth")
    Verse.create!(translation: @kjv, book: deut, chapter: 32, verse_number: 2,
                  text: "My doctrine shall drop as the rain, my speech shall distil as the dew")
    Verse.create!(translation: @kjv, book: gen, chapter: 27, verse_number: 28,
                  text: "Therefore God give thee of the dew of heaven")
    Verse.create!(translation: @kjv, book: matt, chapter: 5, verse_number: 43,
                  text: "Thou shalt love thy neighbour, and hate thine enemy.")
    Verse.create!(translation: @kjv, book: matt, chapter: 5, verse_number: 44,
                  text: "But I say unto you, Love your enemies, bless them that curse you")
  end

  test "verses with every word come first, in Bible order, then partial matches" do
    result = ScriptureSearch.call("dew rain", translation: @kjv)
    assert_equal [ "Deuteronomy 32:2", "Job 38:28", "Genesis 2:5", "Genesis 27:28" ], result.hits.map(&:reference)
    assert_equal %i[ all all partial partial ], result.hits.map(&:tier)
    assert_equal 2, result.all_count
    assert_equal 4, result.any_count
    assert_equal "dew and rain", result.terms_label
  end

  test "the order is the same on every run" do
    runs = 3.times.map { ScriptureSearch.call("Dew doctrine", translation: @kjv).hits.map(&:reference) }
    assert_equal 1, runs.uniq.size
    assert_equal "Deuteronomy 32:2", runs.first.first, "the verse with both words leads"
  end

  test "a phrase as typed ranks above verses that only hold the words" do
    hits = ScriptureSearch.call("love your enemies", translation: @kjv).hits
    assert_equal [ "Matthew 5:44", "Matthew 5:43" ], hits.map(&:reference)
    assert_equal %i[ phrase all ], hits.map(&:tier)
  end

  test "matched words are marked, and the verse text is escaped" do
    hit = ScriptureSearch.call("dew rain", translation: @kjv).hits.first
    html = hit.highlighted
    assert html.html_safe?
    assert_includes html, "<mark>rain</mark>"
    assert_includes html, "<mark>dew</mark>"

    Verse.create!(translation: @kjv, book: Book.find_by_osis("Matt"), chapter: 6, verse_number: 1,
                  text: "<script>alert(1)</script> rain")
    marked = ScriptureSearch.call("rain", translation: @kjv, scope: "Matt").hits.sole.highlighted
    assert_not_includes marked, "<script>"
    assert_includes marked, "&lt;script&gt;"
  end

  test "testament and book filters" do
    assert_equal [ "Matthew 5:43", "Matthew 5:44" ], ScriptureSearch.call("love", translation: @kjv, scope: "nt").hits.map(&:reference)
    assert_empty ScriptureSearch.call("love", translation: @kjv, scope: "ot").hits
    assert_equal [ "Job 38:28" ], ScriptureSearch.call("dew", translation: @kjv, scope: "Job").hits.map(&:reference)
  end

  test "blank and stop-word queries find nothing" do
    assert ScriptureSearch.call("", translation: @kjv).blank?
    assert ScriptureSearch.call("the of and", translation: @kjv).blank?
    assert_empty ScriptureSearch.call("zzqxqwx", translation: @kjv).hits
  end
end
