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

  test "words quoted from a verse find it in the Bible text, without the AI" do
    luke = Book.create!(osis_code: "Luke", name: "Luke", testament: :new, position: 42, chapter_count: 24)
    Verse.create!(translation: @kjv, book: luke, chapter: 12, verse_number: 15,
                  text: "And he said unto them, Take heed, and beware of covetousness: for a man's life consisteth not in the abundance of the things which he possesseth.")
    ai = FakeSearch.new("life consist", error: :api) # the AI isn't reached

    result = ai.call
    assert result.ok?
    assert_equal [ "Luke 12:15" ], result.suggestions.map(&:reference)
    assert_match(/consisteth/, result.suggestions.first.preview)
    assert_equal "", result.summary

    assert_equal [ "Luke 12:15" ], FakeSearch.new("A MAN'S LIFE", error: :api).call.suggestions.map(&:reference)
    assert_equal [ "Luke 12:15" ], FakeSearch.new("take heed and beware", error: :api).call.suggestions.map(&:reference)
  end

  test "single words and unmatched phrases still go to the AI" do
    payload = { topic: "Pentecost", summary: "The Spirit poured out.", references: [ "Acts 2:1" ] }
    assert_equal "Pentecost", FakeSearch.new("pentecost", payload:).call.topic
    assert_equal "Pentecost", FakeSearch.new("tongues of fire upon them", payload:).call.topic
  end
end
