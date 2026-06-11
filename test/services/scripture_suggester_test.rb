require "test_helper"

class ScriptureSuggesterTest < ActiveSupport::TestCase
  # Test double: overrides the network seam (mirrors FakeRabbi / FakePrayer).
  class FakeSuggester < ScriptureSuggester
    def initialize(query, refs: [], error: nil)
      super(query)
      @fake_result =
        if error
          AiChat::Result.new(ok: false, error: error)
        else
          AiChat::Result.new(ok: true, content: { references: refs }.to_json, provider: :gemini)
        end
    end

    private

    def chat_completion = @fake_result
  end

  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @rom = Book.create!(osis_code: "Rom", name: "Romans", testament: :new, position: 45, chapter_count: 16)
    @eph = Book.create!(osis_code: "Eph", name: "Ephesians", testament: :new, position: 49, chapter_count: 6)
    Verse.create!(translation: @kjv, book: @rom, chapter: 5, verse_number: 1, text: "Therefore being justified by faith...")
    Verse.create!(translation: @kjv, book: @eph, chapter: 2, verse_number: 8, text: "For by grace are ye saved through faith...")
  end

  test "blank query short-circuits without calling the API" do
    assert_equal :blank, ScriptureSuggester.call("  ").error
  end

  test "no configured provider reports :no_key" do
    assert_equal :no_key, FakeSuggester.new("grace and works", error: :no_key).call.error
  end

  test "valid references become suggestions; invalid/unknown/duplicate are dropped" do
    result = FakeSuggester.new("saved by grace not works",
      refs: [ "Romans 5:1", "Ephesians 2:8-9", "Nonsense 99:99", "Romans 5:1" ]).call
    assert result.ok?
    assert_equal [ "Romans 5:1", "Ephesians 2:8-9" ], result.suggestions.map(&:reference)
    assert_equal "Therefore being justified by faith...", result.suggestions.first.preview
  end

  test "a provider failure reports :api" do
    assert_equal :api, FakeSuggester.new("anything", error: :api).call.error
  end
end
