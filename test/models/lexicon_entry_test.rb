require "test_helper"

class LexiconEntryTest < ActiveSupport::TestCase
  test "requires strongs and language, unique strongs" do
    LexiconEntry.create!(strongs: "G26", language: "greek")
    dup = LexiconEntry.new(strongs: "G26", language: "greek")
    refute dup.valid?

    blank = LexiconEntry.new
    refute blank.valid?
    assert blank.errors.added?(:strongs, :blank)
    assert blank.errors.added?(:language, :blank)
  end

  test "lookup is case-insensitive on the strongs code" do
    entry = LexiconEntry.create!(strongs: "H7225", language: "hebrew", lemma: "רֵאשִׁית")
    assert_equal entry, LexiconEntry.lookup("h7225")
  end

  test "greek and hebrew scopes" do
    g = LexiconEntry.create!(strongs: "G1", language: "greek")
    h = LexiconEntry.create!(strongs: "H1", language: "hebrew")
    assert_equal [ g ], LexiconEntry.greek.to_a
    assert_equal [ h ], LexiconEntry.hebrew.to_a
  end
end
