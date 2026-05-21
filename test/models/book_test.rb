require "test_helper"

class BookTest < ActiveSupport::TestCase
  test "testament enum is prefixed to avoid the AR `new` collision" do
    b = Book.new(osis_code: "Gen", name: "Genesis", testament: :new, position: 1, chapter_count: 50)
    assert b.testament_new?
    refute b.testament_old?
  end

  test "osis_code and position must be unique" do
    Book.create!(osis_code: "Gen", name: "Genesis", testament: :old, position: 1, chapter_count: 50)
    dup_osis = Book.new(osis_code: "Gen", name: "X", testament: :old, position: 2, chapter_count: 1)
    refute dup_osis.valid?
    dup_pos = Book.new(osis_code: "Exod", name: "Exodus", testament: :old, position: 1, chapter_count: 40)
    refute dup_pos.valid?
  end
end
