require "test_helper"

class RabbiExpositionTest < ActiveSupport::TestCase
  # Test double: overrides the network seam so no live API call is made.
  class FakeRabbi < RabbiExposition
    attr_reader :calls

    def initialize(verse:, selection:, study:, result: nil, verses: nil)
      super(verse:, selection:, study:, verses:)
      @result = result
      @calls = 0
    end

    private

    def chat_completion
      @calls += 1
      @result
    end
  end

  # The test env uses :null_store; swap in a real store to exercise caching.
  def with_memory_cache
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = original
  end

  def fake_ok(content) = AiChat::Result.new(ok: true, content: content, provider: :gemini)

  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    @rom = Book.create!(osis_code: "Rom", name: "Romans", testament: :new, position: 45, chapter_count: 16)
    @v16 = Verse.create!(translation: @kjv, book: @john, chapter: 3, verse_number: 16, text: "For God so loved the world...")
    Verse.create!(translation: @kjv, book: @john, chapter: 3, verse_number: 17, text: "For God sent not his Son...")
    Verse.create!(translation: @kjv, book: @rom, chapter: 5, verse_number: 8, text: "But God commendeth his love...")
    @study = Study.create!(name: "Test study", pane_count: 1)
  end

  test "missing verse reports :no_verse without consulting the model" do
    assert_equal :no_verse, FakeRabbi.new(verse: nil, selection: "anything", study: @study).call.error
  end

  test "blank selection reports :blank" do
    assert_equal :blank, FakeRabbi.new(verse: @v16, selection: "   ", study: @study).call.error
  end

  test "an unconfigured provider surfaces :no_key" do
    result = AiChat::Result.new(ok: false, error: :no_key)
    assert_equal :no_key, FakeRabbi.new(verse: @v16, selection: "loved", study: @study, result:).call.error
  end

  test "parses the exposition and validates every cross-reference against our DB" do
    json = {
      summary: "God's love is the ground of the gospel.",
      context: "The chapter records Jesus and Nicodemus.",
      meaning: "Whoever believes has eternal life.",
      cross_references: [ "Romans 5:8", "Nonsense 99:99", "Romans 5:8" ],
      caution: "Do not read universal salvation into 'world'.",
      application: "Preach the love of God plainly."
    }.to_json

    r = FakeRabbi.new(verse: @v16, selection: "God so loved", study: @study, result: fake_ok(json)).call
    assert r.ok?
    assert_equal "John 3:16", r.origin
    assert_equal "God so loved", r.selection
    assert_equal "God's love is the ground of the gospel.", r.exposition.summary
    assert_equal "Do not read universal salvation into 'world'.", r.exposition.caution
    # invalid + duplicate references are dropped; only valid, known ones survive
    assert_equal [ "Romans 5:8" ], r.cross_references.map(&:reference)
    assert_equal :gemini, r.provider
  end

  test "parses background, and leaves the diagram to the on-demand Draw button" do
    json = {
      summary: "Instructions for the ark.",
      background: "In the ancient Near East a god's throne sat in the innermost room.",
      context: "Exodus 25 gives the tabernacle blueprint.",
      meaning: "The ark is the meeting place of God and Israel.",
      draw_subject: "the ark of the covenant: a gold chest 2.5x1.5x1.5 cubits",
      cross_references: [],
      caution: "Don't allegorise the gold.",
      application: "Teach God's nearness."
    }.to_json

    rabbi = FakeRabbi.new(verse: @v16, selection: "make an ark", study: @study, result: fake_ok(json))
    r = rabbi.call
    assert r.ok?
    assert_equal "In the ancient Near East a god's throne sat in the innermost room.", r.exposition.background
    assert_nil r.exposition.diagram
    assert_equal 1, rabbi.calls, "an exposition costs exactly one model call"
  end

  test "model output is reduced to plain text — no markup or injected links survive" do
    json = {
      summary: "Grace <a href=\"https://evil.example\">click here</a> abounds.",
      meaning: "<script>alert(1)</script>Love &lt;img src=x onerror=alert(1)&gt; wins.",
      caution: "Tom &amp; Jerry", cross_references: []
    }.to_json
    r = FakeRabbi.new(verse: @v16, selection: "loved", study: @study, result: fake_ok(json)).call
    assert r.ok?
    assert_equal "Grace click here abounds.", r.exposition.summary
    assert_not_includes r.exposition.meaning, "<"
    assert_not_includes r.exposition.meaning, "onerror=alert(1)>"
    assert_equal "Tom & Jerry", r.exposition.caution
  end

  test "an identical ask is served from cache without a second model call" do
    json = { summary: "ok", cross_references: [ "Romans 5:8" ] }.to_json
    with_memory_cache do
      first = FakeRabbi.new(verse: @v16, selection: "God so loved", study: @study, result: fake_ok(json))
      assert first.call.ok?
      assert_equal 1, first.calls

      again = FakeRabbi.new(verse: @v16, selection: "  god so LOVED ", study: @study, result: fake_ok(json))
      r = again.call
      assert r.ok?
      assert_equal "ok", r.exposition.summary
      assert_equal [ "Romans 5:8" ], r.cross_references.map(&:reference)
      assert_equal 0, again.calls

      other = FakeRabbi.new(verse: @v16, selection: "the world", study: @study, result: fake_ok(json))
      other.call
      assert_equal 1, other.calls, "a different selection is a different question"
    end
  end

  test "failures are not cached" do
    with_memory_cache do
      FakeRabbi.new(verse: @v16, selection: "loved", study: @study, result: AiChat::Result.new(ok: false, error: :api)).call
      retry_rabbi = FakeRabbi.new(verse: @v16, selection: "loved", study: @study,
                                  result: fake_ok({ summary: "ok" }.to_json))
      assert retry_rabbi.call.ok?
      assert_equal 1, retry_rabbi.calls
    end
  end

  test "the highlighted selection is capped before it reaches the model" do
    rabbi = FakeRabbi.new(verse: @v16, selection: "a" * 5_000, study: @study, result: fake_ok({ summary: "ok" }.to_json))
    assert_equal RabbiExposition::SELECTION_LIMIT, rabbi.call.selection.length
  end

  test "tolerates a code-fenced JSON response" do
    fenced = "```json\n{\"summary\":\"ok\",\"cross_references\":[]}\n```"
    r = FakeRabbi.new(verse: @v16, selection: "loved", study: @study, result: fake_ok(fenced)).call
    assert r.ok?
    assert_equal "ok", r.exposition.summary
  end

  test "unparseable model output reports :api" do
    r = FakeRabbi.new(verse: @v16, selection: "loved", study: @study, result: fake_ok("not json at all")).call
    assert_equal :api, r.error
  end

  test "a highlighted span labels the whole verse range, not just the first" do
    v17 = Verse.find_by(book: @john, chapter: 3, verse_number: 17)
    json = { summary: "ok", cross_references: [] }.to_json
    r = FakeRabbi.new(verse: @v16, verses: [ @v16, v17 ], selection: "loved... sent",
                      study: @study, result: fake_ok(json)).call
    assert r.ok?
    assert_equal "John 3:16–17", r.origin
  end
end
