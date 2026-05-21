require "test_helper"

class HighlightTest < ActiveSupport::TestCase
  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    @verse = Verse.create!(translation: @kjv, book: @john, chapter: 3, verse_number: 16, text: "For God so loved the world")
  end

  test "valid highlight with a sensible range" do
    h = users(:one).highlights.new(verse: @verse, color: :ochre, char_start: 8, char_end: 27)
    assert h.valid?
  end

  test "char_end must be greater than char_start" do
    h = users(:one).highlights.new(verse: @verse, color: :sage, char_start: 10, char_end: 10)
    refute h.valid?
  end

  test "char_start cannot be negative" do
    h = users(:one).highlights.new(verse: @verse, color: :rose, char_start: -1, char_end: 4)
    refute h.valid?
  end

  test "color enum maps to the design tints" do
    assert_equal %w[ochre sage cobalt rose], Highlight.colors.keys
  end
end
