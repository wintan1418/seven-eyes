require "test_helper"

class HymnalTest < ActiveSupport::TestCase
  test "every starter hymn has a title and multi-line body" do
    assert Hymnal::HYMNS.any?
    Hymnal::HYMNS.each do |hymn|
      assert hymn[:title].present?, "a hymn is missing its title"
      assert hymn[:body].present?, "#{hymn[:title]} is missing its body"
      assert hymn[:body].lines.size > 1, "#{hymn[:title]} should have real lyrics"
    end
  end

  test "titles are unique so the library never lists a hymn twice" do
    titles = Hymnal::HYMNS.map { |h| h[:title].downcase }
    assert_equal titles, titles.uniq
  end
end
