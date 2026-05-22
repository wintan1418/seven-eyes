require "test_helper"

class CommentarySeederTest < ActiveSupport::TestCase
  # Subclass that returns canned API responses instead of hitting the network.
  class FakeSeeder < CommentarySeeder
    def fetch_json(url)
      if url.end_with?("books.json")
        { "books" => [ { "id" => "JHN", "order" => 43, "numberOfChapters" => 2 } ] }
      elsif url.end_with?("JHN/1.json")
        { "chapter" => { "content" => [
          { "type" => "verse", "number" => 1, "content" => [ "First thought.\n\nSecond thought." ] }
        ] } }
      elsif url.end_with?("JHN/2.json")
        { "chapter" => { "content" => [
          { "type" => "verse", "number" => 1, "content" => [ "Chapter two note." ] }
        ] } }
      end
    end
  end

  setup do
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
  end

  test "seeds one Commentary row per chapter with assembled HTML paragraphs" do
    FakeSeeder.new("matthew-henry").run

    assert_equal 2, Commentary.where(source: "matthew-henry").count
    ch1 = Commentary.find_by(book: @john, chapter: 1)
    assert_equal "Matthew Henry", ch1.source_name
    assert_includes ch1.body, "<p>First thought.</p>"
    assert_includes ch1.body, "<p>Second thought.</p>"
    assert_includes ch1.body, %(<span class="cm-vref">v. 1</span>)
  end

  test "is idempotent — re-running skips an already-seeded source" do
    FakeSeeder.new("matthew-henry").run
    before = Commentary.where(source: "matthew-henry").maximum(:updated_at)
    FakeSeeder.new("matthew-henry").run
    assert_equal before, Commentary.where(source: "matthew-henry").maximum(:updated_at)
  end

  test "escapes HTML in the source text" do
    seeder = FakeSeeder.new("matthew-henry")
    def seeder.fetch_json(url)
      return { "books" => [ { "id" => "JHN", "order" => 43, "numberOfChapters" => 1 } ] } if url.end_with?("books.json")
      { "chapter" => { "content" => [ { "type" => "verse", "number" => 1, "content" => [ "tags <script> & co" ] } ] } }
    end
    seeder.run
    body = Commentary.find_by(book: @john, chapter: 1).body
    refute_includes body, "<script>"
    assert_includes body, "&lt;script&gt;"
  end
end
