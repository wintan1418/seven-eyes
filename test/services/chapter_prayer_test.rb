require "test_helper"

class ChapterPrayerTest < ActiveSupport::TestCase
  # Subclass seam: override the network call (mirrors FakeRabbi / FakeSuggester).
  class FakeChapterPrayer < ChapterPrayer
    attr_reader :calls
    def initialize(result:, **opts)
      super(**opts)
      @result = result
      @calls = 0
    end

    def chat_completion
      @calls += 1
      @result
    end
  end

  def ai_ok(content)
    AiChat::Result.new(ok: true, content: content, provider: :gemini)
  end

  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    Verse.create!(translation: @kjv, book: @john, chapter: 3, verse_number: 16,
                  text: "For God so loved the world, that he gave his only begotten Son")
  end

  test "returns a prayer drawn from the chapter" do
    svc = FakeChapterPrayer.new(book: @john, chapter: 3,
            result: ai_ok(%({"prayer":"Father, thank you for so loving the world. Amen."})))
    res = svc.call
    assert res.ok?
    assert_equal "John 3", res.reference
    assert_match(/loving the world/, res.prayer)
  end

  test "reports a missing key gracefully" do
    svc = FakeChapterPrayer.new(book: @john, chapter: 3,
            result: AiChat::Result.new(ok: false, error: :no_key))
    res = svc.call
    refute res.ok?
    assert_equal :no_key, res.error
  end

  test "treats blank/garbage content as an api error" do
    svc = FakeChapterPrayer.new(book: @john, chapter: 3, result: ai_ok("not json"))
    refute svc.call.ok?
    assert_equal :api, svc.call.error
  end

  test "refuses a chapter we hold no verses for" do
    res = FakeChapterPrayer.new(book: @john, chapter: 99, result: ai_ok("x")).call
    refute res.ok?
    assert_equal :no_chapter, res.error
  end

  test "caches the prayer so the model is called only once per chapter" do
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    svc = FakeChapterPrayer.new(book: @john, chapter: 3,
            result: ai_ok(%({"prayer":"Lord, teach us. Amen."})))
    svc.call
    svc.call
    assert_equal 1, svc.calls, "second call should be served from cache"
  ensure
    Rails.cache = original
  end
end
