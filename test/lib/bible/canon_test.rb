require "test_helper"

class Bible::CanonTest < ActiveSupport::TestCase
  test "the canon has all 66 Protestant books in order" do
    assert_equal 66, Bible::Canon.all.size
    assert_equal "Gen", Bible::Canon.all.first.osis
    assert_equal "Rev", Bible::Canon.all.last.osis
    assert_equal (1..66).to_a, Bible::Canon.all.map(&:position)
  end

  test "alias map resolves common abbreviations and full names" do
    map = Bible::Canon.alias_map
    assert_equal "John", map["jn"]
    assert_equal "John", map["john"]
    assert_equal "Ps", map["psalm"]
    assert_equal "1Cor", map["1cor"]
    assert_equal "Song", map["songofsolomon"]
    assert_equal "Phlm", map["philemon"]
  end

  test "every book's own osis code resolves to itself" do
    Bible::Canon.all.each do |b|
      assert_equal b.osis, Bible::Canon.alias_map[Bible::Canon.normalize_key(b.osis)]
    end
  end
end
