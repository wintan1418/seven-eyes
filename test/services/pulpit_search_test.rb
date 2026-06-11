require "test_helper"

class PulpitSearchTest < ActiveSupport::TestCase
  # Test double: overrides the network seam (mirrors FakeSuggester / FakeRabbi).
  class FakeSearch < PulpitSearch
    def initialize(query, payload: nil, error: nil)
      super(query)
      @fake_result =
        if error
          AiChat::Result.new(ok: false, error: error)
        else
          AiChat::Result.new(ok: true, content: payload.to_json, provider: :gemini)
        end
    end

    private

    def chat_completion = @fake_result
  end

  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @acts = Book.create!(osis_code: "Acts", name: "Acts", testament: :new, position: 44, chapter_count: 28)
    Verse.create!(translation: @kjv, book: @acts, chapter: 2, verse_number: 1,
                  text: "And when the day of Pentecost was fully come...")
  end

  test "a topic comes back as a projectable card plus validated references" do
    result = FakeSearch.new("azusa street", payload: {
      topic: "Azusa Street Revival",
      summary: "A 1906 revival in Los Angeles led by William J. Seymour, widely seen as the birth of modern Pentecostalism.",
      references: [ "Acts 2:1-4", "Nonsense 99:99", "Acts 2:1-4" ]
    }).call
    assert result.ok?
    assert_equal "Azusa Street Revival", result.topic
    assert_match(/Seymour/, result.summary)
    assert_equal [ "Acts 2:1-4" ], result.suggestions.map(&:reference)
    assert_match(/Pentecost/, result.suggestions.first.preview)
  end

  test "an unsure model (empty summary, no references) reports :nothing" do
    result = FakeSearch.new("zzzz", payload: { topic: "", summary: "", references: [] }).call
    refute result.ok?
    assert_equal :nothing, result.error
  end

  test "references alone are enough when there is no summary" do
    result = FakeSearch.new("pentecost", payload: { topic: "Pentecost", summary: "", references: [ "Acts 2:1" ] }).call
    assert result.ok?
    assert_equal "", result.summary
    assert_equal 1, result.suggestions.size
  end

  test "blank query and provider failures are reported" do
    assert_equal :blank, PulpitSearch.call("  ").error
    assert_equal :no_key, FakeSearch.new("x", error: :no_key).call.error
    assert_equal :api, FakeSearch.new("x", error: :api).call.error
  end
end
