require "test_helper"

class PassageSlugTest < ActiveSupport::TestCase
  test "builds slugs for verse, range, and whole chapter" do
    assert_equal "john-3-16", PassageSlug.slug_for(osis: "John", chapter: 3, verse_start: 16, verse_end: 16)
    assert_equal "john-3",    PassageSlug.slug_for(osis: "John", chapter: 3)
    assert_equal "1-corinthians-13-1-13",
                 PassageSlug.slug_for(osis: "1Cor", chapter: 13, verse_start: 1, verse_end: 13)
    assert_equal "song-of-solomon-2-1",
                 PassageSlug.slug_for(osis: "Song", chapter: 2, verse_start: 1, verse_end: 1)
  end

  test "reverses slugs into reference strings the parser understands" do
    {
      "john-3-16"             => "john 3:16",
      "john-3"                => "john 3",
      "1-corinthians-13-1-13" => "1 corinthians 13:1-13",
      "psalms-23"             => "psalms 23",
      "song-of-solomon-2-1"   => "song of solomon 2:1"
    }.each do |slug, expected|
      assert_equal expected, PassageSlug.reference_for(slug)
      assert ReferenceParser.call(expected).valid?, "#{expected.inspect} should parse"
    end
  end

  test "round-trips through ReferenceParser" do
    %w[John-3-16 1-Corinthians-13 Psalms-23].each do |slug|
      parsed = ReferenceParser.call(PassageSlug.reference_for(slug.downcase))
      rebuilt = PassageSlug.slug_from_result(parsed)
      assert_equal slug.downcase, rebuilt
    end
  end

  test "multi-chapter, cross-chapter and ff passages round-trip" do
    {
      "Matt 5-7"      => "matthew-5-to-7",
      "John 3:16-4:2" => "john-3-16-to-4-2",
      "John 3:16ff"   => "john-3-16-ff",
      "Jude 1-3"      => "jude-1-1-3"
    }.each do |input, slug|
      parsed = ReferenceParser.call(input)
      assert_equal slug, PassageSlug.slug_from_result(parsed), input
      back = ReferenceParser.call(PassageSlug.reference_for(slug))
      assert_equal parsed.label, back.label, slug
    end
    assert_nil PassageSlug.reference_for("john-3-to-x")
  end

  test "returns nil for slugs with no numeric location" do
    assert_nil PassageSlug.reference_for("john")
    assert_nil PassageSlug.reference_for("")
  end
end
