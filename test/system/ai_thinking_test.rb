require "application_system_test_case"

# The Rabbi and illustrations answer from a background job (AiRequest): the
# drawer shows "thinking" at once, polls, and swaps the answer in. A failed
# answer offers Try again. The AI is stubbed — no paid calls.
class AiThinkingTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @user.update!(tour_completed_at: Time.current)
    kjv = Translation.create!(code: "KJV", name: "King James Version")
    john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    @v16 = Verse.create!(translation: kjv, book: john, chapter: 3, verse_number: 16, text: "For God so loved the world")
    @study = @user.studies.create!(name: "Sunday", pane_count: 1)
    @study.panes.first.update!(reference: "John 3", translation: kjv)

    @original_chat = AiChat.method(:call)
    @original_image = OpenaiImage.method(:generate)
    @replies = []
    replies = @replies
    AiChat.singleton_class.define_method(:call) { |*, **| replies.shift || AiChat::Result.new(ok: false, error: :api) }
  end

  teardown do
    AiChat.singleton_class.define_method(:call, @original_chat)
    OpenaiImage.singleton_class.define_method(:generate, @original_image)
  end

  def sign_in
    visit new_session_path
    fill_in "email_address", with: @user.email_address
    fill_in "password", with: "password"
    click_on "Sign In"
    assert_no_current_path new_session_path
  end

  def ask_rabbi
    execute_script(<<~JS, @v16.id)
      window.dispatchEvent(new CustomEvent("rabbi:ask", { detail: { verseId: arguments[0], text: "God so loved" } }))
    JS
  end

  test "a failed answer offers Try again; the retry's answer arrives in the drawer" do
    @replies << AiChat::Result.new(ok: false, error: :api)
    @replies << AiChat::Result.new(ok: true, provider: :gemini,
                                   content: { summary: "The plain love of God.", meaning: "Belief brings life." }.to_json)
    sign_in
    visit study_path(@study)
    wait_for_reader_js
    ask_rabbi

    within(".ps-rabbi-drawer") do
      assert_text "The Rabbi is silent just now."
      click_on "Try again"
      assert_text "The plain love of God."
      assert_text "Belief brings life."

      # …and the illustration paints in the background too.
      @replies << AiChat::Result.new(ok: true, provider: :openai,
                                     content: { illustration: "A father's embrace", caption: "Love given",
                                                annotations: [ { label: "The embrace", note: "the heart" } ] }.to_json)
      OpenaiImage.singleton_class.define_method(:generate) do |*, **|
        OpenaiImage::Result.new(ok: true, data_url: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=")
      end
      click_on "✦ Illustrate this passage"
      assert_selector "img.ps-rabbi-illus-img"
      assert_text "The embrace"
    end
  end
end
