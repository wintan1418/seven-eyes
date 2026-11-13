require "test_helper"

# FaithTermRewriter: the pastor's own words → the glossary fields, with every
# reference and quotation checked against our KJV. AiChat is stubbed.
class FaithTermRewriterTest < ActiveSupport::TestCase
  setup do
    kjv = Translation.create!(code: "KJV", name: "King James Version")
    john1 = Book.create!(osis_code: "1John", name: "1 John", testament: :new, position: 62, chapter_count: 5)
    rom = Book.create!(osis_code: "Rom", name: "Romans", testament: :new, position: 45, chapter_count: 16)
    Verse.create!(translation: kjv, book: john1, chapter: 3, verse_number: 7,
                  text: "Little children, let no man deceive you: he that doeth righteousness is righteous, even as he is righteous.")
    Verse.create!(translation: kjv, book: rom, chapter: 3, verse_number: 22,
                  text: "Even the righteousness of God which is by faith of Jesus Christ unto all and upon all them that believe: for there is no difference:")
    Verse.create!(translation: kjv, book: rom, chapter: 1, verse_number: 17,
                  text: "For therein is the righteousness of God revealed from faith to faith: as it is written, The just shall live by faith.")
    @term = FaithTerm.create!(name: "Righteousness", short_definition: "Old definition.")
    @words = "righteousness is not just u been seen somehow by jesus it is God way of right"
  end

  def reply(overrides = {})
    {
      short_definition: "Righteousness is God's way of right, given to us on the account of faith.",
      new_believer: "God makes you right with Him through faith, and then you do what is right.",
      explanation: "Righteousness is not a title but a function. \"he that doeth righteousness is righteous\" (1 John 3:7).\n\n" \
                   "It is revealed: \"the righteousness of God revealed from faith to faith\" (Romans 1:17).",
      key_references: [ "1 John 3:7", "Rom 3:22", "Hezekiah 4:1", "Romans 99:1", "Romans 1:17" ]
    }.merge(overrides)
  end

  def rewriter(**kw)
    r = FaithTermRewriter.new(term: @term, words: @words, **kw)
    content = @content || reply.to_json
    result = @result || AiChat::Result.new(ok: true, content:, provider: :openai)
    prompts = (@prompts = [])
    r.define_singleton_method(:chat_completion) { prompts << user_prompt; result }
    r
  end

  test "parses the JSON into the four fields" do
    result = rewriter.call
    assert result.ok?
    s = result.suggestion
    assert_match(/God's way of right/, s[:short_definition])
    assert_match(/through faith/, s[:new_believer])
    assert_equal 2, s[:explanation].split("\n\n").size
    assert_equal :openai, result.provider
  end

  test "drops references that don't parse or aren't in our KJV, and labels the rest" do
    result = rewriter.call
    assert_equal [ "1 John 3:7", "Romans 3:22", "Romans 1:17" ], result.suggestion[:key_references]
    assert_includes result.dropped_references, "Hezekiah 4:1"
    assert_includes result.dropped_references, "Romans 99:1"
  end

  test "checks each quotation against the KJV verse it cites" do
    result = rewriter.call
    assert_equal 2, result.quote_checks.size
    assert result.quote_checks.all? { |c| c[:ok] }
    assert_empty result.unchecked_quotes

    @content = reply(explanation: "\"Whosoever doeth good is righteous forever\" (1 John 3:7). \"a righteousness of works\" stands alone.").to_json
    bad = rewriter.call.unchecked_quotes
    assert_equal [ "1 John 3:7", nil ], bad.map { |c| c[:reference] }
  end

  test "the prompt carries the term, the current text, his words and the chosen chips" do
    rewriter(chips: [ "shorter", "keep_wording", "nonsense" ],
             current: { short_definition: "Unsaved edit.", key_references: "Romans 3:22\n1 John 3:7" }).call
    prompt = @prompts.last
    assert_match "TERM: Righteousness", prompt
    assert_match "Unsaved edit.", prompt
    assert_match "Romans 3:22; 1 John 3:7", prompt
    assert_match @words, prompt
    assert_match(/Shorter:/, prompt)
    assert_match(/Keep my wording:/, prompt)
    assert_no_match(/nonsense/, prompt)
    assert_no_match(/Simpler:/, prompt)
  end

  test "the system prompt keeps his doctrine and quotes only the KJV" do
    assert_match(/Do not soften/, FaithTermRewriter::SYSTEM_PROMPT)
    assert_match(/ONLY the King James Version/, FaithTermRewriter::SYSTEM_PROMPT)
    assert_match(/Never invent/, FaithTermRewriter::SYSTEM_PROMPT)
  end

  test "a follow-up carries the conversation so far" do
    history = { "requests" => [ "Rewrite from my words" ], "last" => { "short_definition" => "Draft one.", "key_references" => [ "Romans 3:22" ] } }
    r = rewriter(request: "make it shorter", history: history.to_json)
    result = r.call
    prompt = @prompts.last
    assert_match "YOUR LAST DRAFT:\nshort_definition: Draft one.", prompt
    assert_match "- Rewrite from my words", prompt
    assert_match "CHANGE REQUEST NOW: make it shorter", prompt

    nxt = r.next_history(result.suggestion)
    assert_equal [ "Rewrite from my words", "make it shorter" ], nxt["requests"]
    assert_equal result.suggestion[:short_definition], nxt["last"]["short_definition"]
  end

  test "history is trimmed to the last few turns and junk is ignored" do
    many = { "requests" => (1..10).map { "ask #{_1}" }, "last" => "not a hash" }
    clean = FaithTermRewriter.clean_history(many.to_json)
    assert_equal FaithTermRewriter::HISTORY_TURNS, clean["requests"].size
    assert_equal({}, clean["last"])
    assert_equal({}, FaithTermRewriter.clean_history("{not json"))
  end

  test "no AI key fails gracefully" do
    @result = AiChat::Result.new(ok: false, error: :no_key)
    result = rewriter.call
    assert_not result.ok?
    assert_equal :no_key, result.error
  end

  test "a provider failure or a non-JSON answer is an :api error" do
    @result = AiChat::Result.new(ok: false, error: :api)
    assert_equal :api, rewriter.call.error
    @result = nil
    @content = "Sorry, I can't help with that."
    assert_equal :api, rewriter.call.error
  end

  test "nothing to rewrite without words or a request, and no AI call" do
    r = FaithTermRewriter.new(term: @term, words: "  ")
    r.define_singleton_method(:chat_completion) { raise "should not call" }
    assert_equal :blank, r.call.error
  end

  test "markup in the answer is stripped" do
    @content = reply(short_definition: "<b>Righteousness</b> <a href='x'>is</a> right.").to_json
    assert_equal "Righteousness is right.", rewriter.call.suggestion[:short_definition]
  end
end
