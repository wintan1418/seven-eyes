require "test_helper"

class VerseTokenSeederTest < ActiveSupport::TestCase
  def tok(raw, prefix = "G")
    VerseTokenSeeder.new.tokenize(raw, prefix)
  end

  test "tags each word with its Strong's number and reconstructs the text" do
    raw = "For<S>1063</S> God<S>2316</S> so<S>3779</S> loved<S>25</S> the world<S>2889</S>"
    tokens = tok(raw)
    assert_equal "G1063", tokens.first["s"]
    assert_equal "For", tokens.first["w"]
    assert_equal "G2889", tokens.last["s"]
    assert_equal "For God so loved the world", tokens.map { |t| t["w"] }.join
  end

  test "uses the given language prefix" do
    tokens = tok("beginning<S>7225</S>", "H")
    assert_equal "H7225", tokens.first["s"]
  end

  test "keeps untranslated particles as plain text, not clickable words" do
    # The Hebrew object-marker 853 has no English word — only a space precedes it.
    tokens = tok("created<S>1254</S> <S>853</S> the heaven<S>8064</S>", "H")
    assert_equal "H1254", tokens[0]["s"]
    refute tokens[1].key?("s"), "the bare space must not become a clickable word"
    assert_equal "H8064", tokens[2]["s"]
    assert_equal "created  the heaven", tokens.map { |t| t["w"] }.join
  end

  test "drops translators' marginal notes in <sup> together with their text" do
    raw = "Blessed<S>835</S> are the undefiled<S>8549</S> in the way<S>1870</S>. <sup>undefiled: or, perfect, or, sincere</sup>"
    tokens = tok(raw, "H")
    assert_equal "Blessed are the undefiled in the way.", tokens.map { |t| t["w"] }.join.squish
    refute tokens.map { |t| t["w"] }.join.include?("sincere")
  end

  test "tokens_for keeps tokens only when they spell the stored verse" do
    seeder = VerseTokenSeeder.new
    verse = Verse.new(text: "Blessed are the undefiled in the way.")
    ok = seeder.tokens_for(verse, "Blessed<S>835</S> are the undefiled<S>8549</S> in the way<S>1870</S>.", "H")
    assert_equal "H835", ok.first["s"]

    psalm = seeder.tokens_for(verse, "ALEPH. Blessed<S>835</S> are the undefiled<S>8549</S> in the way<S>1870</S>.", "H")
    assert psalm, "the Psalm 119 stanza letter is not part of the verse"
    assert_equal "Blessed", psalm.first["w"]

    assert_nil seeder.tokens_for(verse, "Happy<S>835</S> are the perfect<S>8549</S>.", "H")
  end

  test "strips non-Strong's markup (italics, footnotes)" do
    tokens = tok("the <i>LORD</i> God<S>430</S>", "H")
    assert_equal "the LORD God", tokens.map { |t| t["w"] }.join
    assert_equal "H430", tokens.last["s"]
  end
end
