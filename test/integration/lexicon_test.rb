require "test_helper"

class LexiconEndpointTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    Verse.create!(translation: @kjv, book: @john, chapter: 3, verse_number: 16,
                  text: "For God so loved the world",
                  tokens: [ { "w" => "loved", "s" => "G26" } ])
    LexiconEntry.create!(strongs: "G26", language: "greek", lemma: "ἀγάπη", translit: "agápē",
                         definition: "love, affection or benevolence", kjv_def: "love, charity")
    @study = users(:one).studies.create!(name: "S", pane_count: 2)
  end

  test "lexicon renders the word-study frame with lemma, definition, and occurrences" do
    get lexicon_study_path(@study, strongs: "G26")
    assert_response :success
    assert_select "turbo-frame#lexicon_drawer"
    assert_includes response.body, "ἀγάπη"
    assert_includes response.body, "agápē"
    assert_includes response.body, "love, affection or benevolence"
    assert_includes response.body, "John 3:16"
    assert_select "form[data-turbo-frame=?]", @study.panes.first.frame_id
  end

  test "unknown strongs number renders a graceful empty entry" do
    get lexicon_study_path(@study, strongs: "G99999")
    assert_response :success
    assert_includes response.body, "No lexicon entry"
  end
end
