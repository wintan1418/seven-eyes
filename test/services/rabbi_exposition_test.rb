require "test_helper"

class RabbiExpositionTest < ActiveSupport::TestCase
  # Test double: overrides the network seam so no live API call is made.
  class FakeRabbi < RabbiExposition
    def initialize(verse:, selection:, study:, result: nil)
      super(verse:, selection:, study:)
      @result = result
    end

    private

    def chat_completion = @result
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

  test "parses background and a sanitised diagram for a physical passage" do
    json = {
      summary: "Instructions for the ark.",
      background: "In the ancient Near East a god's throne sat in the innermost room.",
      context: "Exodus 25 gives the tabernacle blueprint.",
      meaning: "The ark is the meeting place of God and Israel.",
      diagram: "<svg viewBox='0 0 100 60'><script>x()</script>" \
               "<rect x='2' y='2' width='60' height='30' stroke='#3a2a18' fill='none'/>" \
               "<text x='6' y='50'>2.5 cubits (~3.75 ft)</text></svg>",
      cross_references: [],
      caution: "Don't allegorise the gold.",
      application: "Teach God's nearness."
    }.to_json

    r = FakeRabbi.new(verse: @v16, selection: "make an ark", study: @study, result: fake_ok(json)).call
    assert r.ok?
    assert_equal "In the ancient Near East a god's throne sat in the innermost room.", r.exposition.background
    assert r.exposition.diagram.present?
    assert r.exposition.diagram.html_safe?
    assert_includes r.exposition.diagram, "2.5 cubits"
    assert_not_includes r.exposition.diagram, "script" # scrubbed
  end

  test "a non-physical passage yields no diagram" do
    json = { summary: "ok", diagram: "", cross_references: [] }.to_json
    r = FakeRabbi.new(verse: @v16, selection: "loved", study: @study, result: fake_ok(json)).call
    assert r.ok?
    assert_nil r.exposition.diagram
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
end
