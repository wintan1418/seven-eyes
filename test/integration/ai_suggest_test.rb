require "test_helper"

class AiSuggestTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @study = users(:one).studies.create!(name: "S", pane_count: 2)
  end

  # Temporarily replace ScriptureSuggester.call (no network) and restore after.
  def with_result(result)
    original = ScriptureSuggester.method(:call)
    ScriptureSuggester.define_singleton_method(:call) { |*_args, **_kw| result }
    yield
  ensure
    ScriptureSuggester.define_singleton_method(:call, original)
  end

  test "suggest renders the no-key notice when unconfigured" do
    with_result(ScriptureSuggester::Result.new(ok: false, error: :no_key)) do
      get suggest_study_path(@study), params: { q: "grace" }
    end
    assert_response :success
    assert_includes response.body, "OPENAI_API_KEY"
  end

  test "suggest renders suggestions with per-pane load buttons" do
    suggestion = ScriptureSuggester::Suggestion.new(
      reference: "Romans 5:1", osis: "Rom", chapter: 5, verse_start: 1, verse_end: 1,
      preview: "Therefore being justified by faith..."
    )
    result = ScriptureSuggester::Result.new(ok: true, suggestions: [ suggestion ])
    with_result(result) do
      get suggest_study_path(@study), params: { q: "saved by grace" }
    end
    assert_response :success
    assert_select "turbo-frame#ai_results"
    assert_includes response.body, "Romans 5:1"
    assert_select "form[data-turbo-frame=?]", @study.panes.first.frame_id
  end
end
