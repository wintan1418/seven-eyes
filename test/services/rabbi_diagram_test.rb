require "test_helper"

class RabbiDiagramTest < ActiveSupport::TestCase
  class FakeDiagram < RabbiDiagram
    def initialize(verse:, study:, selection: nil, result: nil)
      super(verse:, selection:, study:)
      @result = result
    end

    private

    def chat_completion = @result
  end

  def fake_ok(content) = AiChat::Result.new(ok: true, content: content, provider: :gemini)

  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @exod = Book.create!(osis_code: "Exod", name: "Exodus", testament: :old, position: 2, chapter_count: 40)
    @v10 = Verse.create!(translation: @kjv, book: @exod, chapter: 25, verse_number: 10,
                         text: "And they shall make an ark of shittim wood...")
    Verse.create!(translation: @kjv, book: @exod, chapter: 25, verse_number: 11, text: "And thou shalt overlay it...")
    @study = Study.create!(name: "Test", pane_count: 1)
  end

  test "missing verse reports :no_verse" do
    assert_equal :no_verse, FakeDiagram.new(verse: nil, study: @study).call.error
  end

  test "an unconfigured provider surfaces :no_key" do
    res = AiChat::Result.new(ok: false, error: :no_key)
    assert_equal :no_key, FakeDiagram.new(verse: @v10, study: @study, result: res).call.error
  end

  test "returns a sanitised svg from a JSON {svg:...} response" do
    svg = "<svg viewBox='0 0 480 320'><script>x()</script>" \
          "<rect x='120' y='120' width='240' height='90' stroke='#3a2a18' fill='none'/>" \
          "<text x='240' y='240'>2.5 cubits (~3.75 ft)</text></svg>"
    r = FakeDiagram.new(verse: @v10, study: @study, result: fake_ok({ svg: svg }.to_json)).call
    assert r.ok?
    assert r.svg.html_safe?
    assert_includes r.svg, "2.5 cubits"
    assert_not_includes r.svg, "script"
    assert_equal "Exodus 25:10", r.origin
  end

  test "also accepts a raw <svg> response as a fallback" do
    raw = "<svg viewBox='0 0 10 10'><rect width='5' height='5' stroke='#3a2a18'/></svg>"
    r = FakeDiagram.new(verse: @v10, study: @study, result: fake_ok(raw)).call
    assert r.ok?
  end

  test "an empty {svg:\"\"} response reports :none" do
    r = FakeDiagram.new(verse: @v10, study: @study, result: fake_ok('{"svg":""}')).call
    assert_equal :none, r.error
  end
end
