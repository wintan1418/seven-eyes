require "test_helper"

class PassageGapsTest < ActiveSupport::TestCase
  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @bsb = Translation.create!(code: "BSB", name: "Berean Standard Bible")
    @dra = Translation.create!(code: "DRA", name: "Douay-Rheims")
    @matt = Book.create!(osis_code: "Matt", name: "Matthew", testament: :new, position: 40, chapter_count: 28)
    (9..12).each { |v| Verse.create!(translation: @kjv, book: @matt, chapter: 18, verse_number: v, text: "k#{v}") }
    [ 9, 10, 12 ].each { |v| Verse.create!(translation: @bsb, book: @matt, chapter: 18, verse_number: v, text: "b#{v}") }
    Verse.create!(translation: @dra, book: @matt, chapter: 19, verse_number: 1, text: "d")
  end

  def verses(t) = Verse.where(translation: t, book: @matt).ordered.to_a

  test "within finds verses missing inside the shown span" do
    assert_equal [ [ 18, 11 ] ], PassageGaps.within(verses(@bsb), ReferenceParser.call("Matt 18:9-12"))
    assert_equal [], PassageGaps.within(verses(@kjv), ReferenceParser.call("Matt 18:9-12"))
  end

  test "within counts from verse 1 for a whole chapter" do
    gaps = PassageGaps.within(verses(@bsb), ReferenceParser.call("Matt 18"))
    assert_equal (1..8).map { |v| [ 18, v ] } + [ [ 18, 11 ] ], gaps
  end

  test "alternative_for prefers the KJV for missing verses" do
    assert_equal @kjv, PassageGaps.alternative_for(book: @matt, translation: @bsb, locations: [ [ 18, 11 ] ])
    assert_nil PassageGaps.alternative_for(book: @matt, translation: @bsb, locations: [ [ 18, 40 ] ])
  end

  test "alternative_for a chapter skips Vulgate-numbered translations" do
    assert_nil PassageGaps.alternative_for(book: @matt, translation: @kjv, chapter: 19)
    assert_equal @kjv, PassageGaps.alternative_for(book: @matt, translation: @bsb, chapter: 18)
  end
end
