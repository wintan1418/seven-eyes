require "test_helper"

class DailyWordComposerTest < ActiveSupport::TestCase
  # Subclass seam: override the network call (mirrors FakeChapterPrayer).
  class FakeComposer < DailyWordComposer
    attr_reader :prompt
    def initialize(word, result:)
      super(word)
      @result = result
    end

    def chat_completion
      @prompt = user_prompt
      @result
    end
  end

  def ai_ok(content) = AiChat::Result.new(ok: true, content:, provider: :gemini)

  setup do
    kjv = Translation.create!(code: "KJV", name: "King James Version")
    john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    (14..18).each do |n|
      Verse.create!(translation: kjv, book: john, chapter: 3, verse_number: n, text: "John three verse #{n}")
    end
    @word = DailyWord.create!(date: Date.new(2026, 11, 11), reference: "John 3:16", osis_code: "John", chapter: 3,
                              verse_start: 16, verse_end: 16, translation_code: "KJV", verse_text: "John three verse 16")
  end

  test "returns a reflection and prayer, and grounds the prompt in the surrounding verses" do
    svc = FakeComposer.new(@word, result: ai_ok(%({"reflection":"God gave his Son. Rest in that love today.","prayer":"Father, thank you. Amen."})))
    res = svc.call
    assert res.ok?
    assert_equal "God gave his Son. Rest in that love today.", res.reflection
    assert_equal "Father, thank you. Amen.", res.prayer
    assert_includes svc.prompt, "14. John three verse 14"
    assert_includes svc.prompt, "18. John three verse 18"
  end

  test "strips markup and links from the model's answer" do
    content = %({"reflection":"<b>Love</b> <a href='https://evil.example'>click</a> &lt;script&gt;","prayer":"<i>Amen.</i>"})
    res = FakeComposer.new(@word, result: ai_ok(content)).call
    assert res.ok?
    assert_no_match(/[<>]|href/, res.reflection)
    assert_equal "Amen.", res.prayer
  end

  test "accepts a fenced JSON answer" do
    res = FakeComposer.new(@word, result: ai_ok(%(```json\n{"reflection":"R.","prayer":"P. Amen."}\n```))).call
    assert res.ok?
  end

  test "no key, a spent budget or a failed provider fail soft" do
    %i[ no_key budget api ].each do |code|
      res = FakeComposer.new(@word, result: AiChat::Result.new(ok: false, error: code)).call
      refute res.ok?
      assert_equal code, res.error
    end
  end

  test "garbage or half answers are treated as failures" do
    [ "not json", %({"reflection":"Only this"}), %(["a"]), "" ].each do |content|
      refute FakeComposer.new(@word, result: ai_ok(content)).call.ok?, content
    end
  end

  test "a raised error never escapes" do
    svc = FakeComposer.new(@word, result: nil)
    refute svc.call.ok?
  end

  test "the real AiChat path respects a missing key without a network call" do
    with_env(%w[ OPENAI_API_KEY OPENAI_KEY Google_GEMINI_API_KEY GEMINI_API_KEY ROUTELLM_API_KEY ABACUS_API_KEY ]) do
      res = DailyWordComposer.call(@word)
      refute res.ok?
      assert_equal :no_key, res.error
    end
  end

  private

  def with_env(keys)
    saved = keys.to_h { |k| [ k, ENV.delete(k) ] }
    yield
  ensure
    saved.each { |k, v| ENV[k] = v if v }
  end
end
