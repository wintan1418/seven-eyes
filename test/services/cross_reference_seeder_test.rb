require "test_helper"

class CrossReferenceSeederTest < ActiveSupport::TestCase
  # Subclass that yields canned TSV lines instead of downloading + unzipping.
  class FakeSeeder < CrossReferenceSeeder
    LINES = [
      "Gen.1.1\tJohn.1.1-John.1.3\t50",
      "Gen.1.1\tPs.8.4\t12",
      "Ps.8.4\tGen.1.1\t9",
      "Zzz.1.1\tGen.1.1\t99" # unknown book — must be skipped, not crash
    ].freeze

    private

    def each_data_line(&) = LINES.each(&)
  end

  setup do
    @gen = Book.create!(osis_code: "Gen", name: "Genesis", testament: :old, position: 1, chapter_count: 50)
    @ps = Book.create!(osis_code: "Ps", name: "Psalms", testament: :old, position: 19, chapter_count: 150)
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
  end

  test "seeds rows, resolving books by OSIS code and parsing ranges" do
    FakeSeeder.seed!

    assert_equal 3, CrossReference.count
    range = CrossReference.find_by(from_book: @gen, to_book: @john)
    assert_equal [ 1, 1, 1, 1, 3 ],
      [ range.from_chapter, range.from_verse, range.to_chapter_start, range.to_verse_start, range.to_verse_end ]
    assert_equal 1, CrossReference.for_verse(book_id: @ps.id, chapter: 8, verse: 4).count
  end

  test "refuses to run against an empty Book table instead of silently seeding nothing" do
    Book.delete_all
    error = assert_raises(RuntimeError) { FakeSeeder.seed! }
    assert_match(/bibles:seed/, error.message)
    assert_equal 0, CrossReference.count
  end

  test "a range running into the next book keeps just its start verse" do
    seeder = Class.new(CrossReferenceSeeder) do
      private

      def each_data_line(&) = [ "Gen.1.1\tPs.150.6-John.1.1\t5" ].each(&)
    end
    seeder.seed!
    ref = CrossReference.last
    assert_equal [ 150, 6, nil, nil ], [ ref.to_chapter_start, ref.to_verse_start, ref.to_chapter_end, ref.to_verse_end ]
    assert_equal "Psalms 150:6", ref.to_label
  end

  test "is idempotent — a second run without force leaves the table alone" do
    FakeSeeder.seed!
    before_ids = CrossReference.order(:id).pluck(:id)
    FakeSeeder.seed!
    assert_equal before_ids, CrossReference.order(:id).pluck(:id)
  end
end
