require "test_helper"

# POST /admin/faith/:slug/rewrite — "Rewrite with AI" on the review desk.
# Reviewers and admins get a suggestion in the faith_rewrite frame; nothing is
# saved. AiChat is stubbed.
class FaithTermRewriteTest < ActionDispatch::IntegrationTest
  setup do
    kjv = Translation.create!(code: "KJV", name: "King James Version")
    rom = Book.create!(osis_code: "Rom", name: "Romans", testament: :new, position: 45, chapter_count: 16)
    Verse.create!(translation: kjv, book: rom, chapter: 3, verse_number: 22,
                  text: "Even the righteousness of God which is by faith of Jesus Christ unto all and upon all them that believe")
    @term = FaithTerm.create!(name: "Righteousness", short_definition: "Old definition.", explanation: "Old explanation.",
                              key_references: [ "Romans 3:22" ])
    @reply = AiChat::Result.new(ok: true, provider: :openai, content: {
      short_definition: "Righteousness is God's way of right, given on the account of faith.",
      new_believer: "God puts you right through faith.",
      explanation: "\"the righteousness of God which is by faith\" (Romans 3:22).\n\nIt is a function, not a title.",
      key_references: [ "Romans 3:22", "Opinions 1:1" ]
    }.to_json)
    Rails.cache.clear
  end

  def with_ai_result(result)
    original = AiChat.method(:call)
    calls = 0
    AiChat.singleton_class.define_method(:call) { |*, **| calls += 1; result }
    yield -> { calls }
  ensure
    AiChat.singleton_class.define_method(:call, original)
  end

  def rewrite(**extra)
    post rewrite_admin_faith_term_path(@term), params: { words: "righteousness is not a title but a function",
                                                         current: { short_definition: "Old definition." } }.merge(extra)
  end

  test "an admin gets the suggestion beside the current text, and nothing is saved" do
    users(:one).update!(admin: true)
    sign_in_as users(:one)
    before = @term.reload.attributes
    with_ai_result(@reply) { rewrite }
    assert_response :success
    assert_select "turbo-frame#faith_rewrite" do
      assert_select ".fr-field[data-field=short_definition] .fr-now", /Old definition/
      assert_select ".fr-field[data-field=short_definition] .fr-new", /God's way of right/
      assert_select "button.fr-use[data-field=key_references][data-value=?]", "Romans 3:22"
      assert_select ".fr-warn", /Opinions 1:1/
      assert_select ".fr-ok", /1 quotation checked/
      assert_select "button.fr-use-all", "Use all"
      assert_select "textarea[name=follow_up][form=faith-rewrite-form]"
      assert_select "input#fr-history[form=faith-rewrite-form]"
    end
    history = JSON.parse(css_select("#fr-history").first["value"])
    assert_equal [ "Rewrite from my words" ], history["requests"]
    assert_equal before, @term.reload.attributes
    assert @term.draft?
  end

  test "a reviewer (not admin) can use it too, and the edit page shows the panel" do
    users(:two).update!(reviewer: true)
    sign_in_as users(:two)
    get edit_admin_faith_term_path(@term)
    assert_select ".fr-panel form#faith-rewrite-form[action=?]", rewrite_admin_faith_term_path(@term)
    assert_select ".fr-chip input[name='chips[]']", 4
    with_ai_result(@reply) { rewrite(chips: [ "shorter" ]) }
    assert_response :success
    assert_select ".fr-new", /God's way of right/
  end

  test "the public and ordinary users can't call it, and no AI call is made" do
    with_ai_result(@reply) do |calls|
      rewrite
      assert_redirected_to new_session_path

      sign_in_as users(:one)
      rewrite
      assert_redirected_to root_path
      assert_equal 0, calls.call
    end
    assert_equal "Old definition.", @term.reload.short_definition
  end

  test "no AI key: a clear message in the frame" do
    users(:one).update!(admin: true)
    sign_in_as users(:one)
    with_ai_result(AiChat::Result.new(ok: false, error: :no_key)) { rewrite }
    assert_response :success
    assert_select "turbo-frame#faith_rewrite .fr-error", /isn.t set up on this server/
  end

  test "a reviewer's daily AI allowance is respected" do
    refuse_daily
    assert_response :too_many_requests
    assert_select "turbo-frame#faith_rewrite .fr-error", /allowance is used up/
  end

  def refuse_daily
    users(:one).update!(admin: true)
    sign_in_as users(:one)
    original = AiBudget.method(:charge_user)
    AiBudget.singleton_class.define_method(:charge_user) { |*| false }
    with_ai_result(@reply) { rewrite }
  ensure
    AiBudget.singleton_class.define_method(:charge_user, original) if original
  end
end
