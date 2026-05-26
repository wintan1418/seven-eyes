require "test_helper"

class InterlinearTest < ActionDispatch::IntegrationTest
  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @john = Book.create!(osis_code: "John", name: "John", testament: :new,
                         position: 43, chapter_count: 21)
    Verse.create!(translation: @kjv, book: @john, chapter: 3, verse_number: 16,
                  text: "For God so loved the world",
                  tokens: [
                    { "w" => "For" },
                    { "s" => "G2316", "w" => "God" },
                    { "w" => "so" },
                    { "s" => "G25", "w" => "loved" },
                    { "w" => "the" },
                    { "s" => "G2889", "w" => "world" }
                  ])
    LexiconEntry.create!(strongs: "G2316", language: "greek", lemma: "θεός", translit: "theos")
    LexiconEntry.create!(strongs: "G25",   language: "greek", lemma: "ἀγαπάω", translit: "agapaō")

    @user = users(:one)
    sign_in_as @user
    @study = @user.studies.create!(name: "Word study", pane_count: 1)
    @study.panes.first.update!(reference: "John 3:16", translation: @kjv)
  end

  test "tagged words carry data-strongs and data-gloss with translit · Strong's" do
    get study_path(@study)
    assert_response :success
    assert_select "a.ps-word[data-strongs='G2316'][data-gloss=?]", "theos · G2316"
    assert_select "a.ps-word[data-strongs='G25'][data-gloss=?]", "agapaō · G25"
  end

  test "tagged word without a lexicon entry still shows the Strong's number" do
    get study_path(@study)
    # G2889 (world) has no lexicon entry — gloss falls back to the code alone.
    assert_select "a.ps-word[data-strongs='G2889'][data-gloss='G2889']"
  end

  test "topbar exposes the Lemma toggle wired to the interlinear controller" do
    get study_path(@study)
    assert_select "[data-action=?]", "interlinear#toggle"
    assert_select "[data-interlinear-target=?]", "button"
  end
end
