require "test_helper"

class PlanTemplateTest < ActiveSupport::TestCase
  setup do
    @gen = Book.create!(osis_code: "Gen", name: "Genesis", testament: :old, position: 1, chapter_count: 50)
    @matt = Book.create!(osis_code: "Matt", name: "Matthew", testament: :new, position: 40, chapter_count: 28)
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
  end

  test "empty template returns no days" do
    assert_equal [], PlanTemplate.build("empty")
  end

  test "book template paces a single book at N chapters/day" do
    days = PlanTemplate.build("book", book: "John", chapters_per_day: 3)
    assert_equal 7, days.size
    assert_equal({ day_number: 1, refs: "John 1, John 2, John 3" }, days.first)
    assert_equal({ day_number: 7, refs: "John 19, John 20, John 21" }, days.last)
  end

  test "book template defaults to 1 chapter/day" do
    days = PlanTemplate.build("book", book: "John")
    assert_equal 21, days.size
  end

  test "new_testament template spreads NT chapters across the requested days" do
    days = PlanTemplate.build("new_testament", days: 7)
    assert_equal 7, days.size
    assert days.all? { |d| d[:refs].length.positive? }
  end

  test "unknown template kind returns empty" do
    assert_equal [], PlanTemplate.build("nonsense")
  end
end
