require "test_helper"

class ScriptureHelperTest < ActionView::TestCase
  setup do
    @gen = Book.create!(osis_code: "Gen", name: "Genesis", testament: :old, position: 1, chapter_count: 50)
    @exo = Book.create!(osis_code: "Exod", name: "Exodus", testament: :old, position: 2, chapter_count: 40)
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    @acts = Book.create!(osis_code: "Acts", name: "Acts", testament: :new, position: 44, chapter_count: 28)
  end

  test "neighbor_reference returns the next chapter within a book" do
    assert_equal "John 4", neighbor_reference(@john, 3, :next)
  end

  test "neighbor_reference returns the previous chapter within a book" do
    assert_equal "John 2", neighbor_reference(@john, 3, :prev)
  end

  test "neighbor_reference wraps to the next book at the end of one" do
    assert_equal "Acts 1", neighbor_reference(@john, 21, :next)
  end

  test "neighbor_reference wraps to the previous book at chapter 1" do
    assert_equal "Genesis 50", neighbor_reference(@exo, 1, :prev)
  end

  test "neighbor_reference returns nil at the very start of the canon" do
    assert_nil neighbor_reference(@gen, 1, :prev)
  end
end
