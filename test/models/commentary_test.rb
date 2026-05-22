require "test_helper"

class CommentaryTest < ActiveSupport::TestCase
  setup do
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
  end

  test "requires source, source_name, chapter, and body" do
    c = Commentary.new(book: @john)
    refute c.valid?
    assert c.errors.added?(:source, :blank)
    assert c.errors.added?(:body, :blank)
    assert c.errors.added?(:chapter, :blank)
  end

  test "source is unique per book and chapter" do
    Commentary.create!(source: "matthew-henry", source_name: "Matthew Henry", book: @john, chapter: 3, body: "x")
    dup = Commentary.new(source: "matthew-henry", source_name: "Matthew Henry", book: @john, chapter: 3, body: "y")
    refute dup.valid?
  end

  test "for_chapter returns matching entries ordered by source name" do
    Commentary.create!(source: "matthew-henry", source_name: "Matthew Henry", book: @john, chapter: 3, body: "mh")
    Commentary.create!(source: "adam-clarke", source_name: "Adam Clarke", book: @john, chapter: 3, body: "ac")
    Commentary.create!(source: "matthew-henry", source_name: "Matthew Henry", book: @john, chapter: 4, body: "other")

    rows = Commentary.for_chapter(@john, 3)
    assert_equal %w[Adam\ Clarke Matthew\ Henry], rows.map(&:source_name)
  end
end
