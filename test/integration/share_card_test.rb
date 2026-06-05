require "test_helper"

class ShareCardTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    @v16 = Verse.create!(translation: @kjv, book: @john, chapter: 3, verse_number: 16,
                         text: "For God so loved the world, that he gave his only begotten Son")
    @study = users(:one).studies.create!(name: "S", pane_count: 1)
  end

  test "share_card returns card metadata for a single verse" do
    get share_card_study_path(@study), params: { verse_id: @v16.id }
    assert_response :success
    data = JSON.parse(response.body)
    assert_equal "John 3:16", data["reference"]
    assert_equal "John", data["osis"]
    assert_equal "john-3-16", data["slug"]
    assert_includes data["url"], "/p/john-3-16"
    assert_includes data["text"], "only begotten Son"
  end

  test "share_card honours a highlighted selection for the card text" do
    get share_card_study_path(@study), params: { verse_id: @v16.id, q: "God so loved the world" }
    data = JSON.parse(response.body)
    assert_equal "God so loved the world", data["text"]
  end

  test "share_card resolves a whole-chapter passage from osis + chapter" do
    get share_card_study_path(@study), params: { osis: "John", chapter: 3, translation: "KJV" }
    assert_response :success
    data = JSON.parse(response.body)
    assert_equal "John 3", data["reference"]
    assert_equal "john-3", data["slug"]
  end

  test "share_card 404s for an unknown book" do
    get share_card_study_path(@study), params: { osis: "Nope", chapter: 1 }
    assert_response :not_found
  end

  # Swap AiChat.call for a canned result (no live network). minitest 6 dropped
  # #stub, so we juggle the singleton method (mirrors rabbi_test).
  def with_ai_result(result)
    original = AiChat.method(:call)
    AiChat.singleton_class.define_method(:call) { |*, **| result }
    yield
  ensure
    AiChat.singleton_class.define_method(:call, original)
  end

  test "prayer endpoint returns a composed prayer" do
    with_ai_result(AiChat::Result.new(ok: true, provider: :gemini,
        content: %({"prayer":"Father, thank you for so loving the world. Amen."}))) do
      get prayer_study_path(@study), params: { osis: "John", chapter: 3 }
    end
    assert_response :success
    data = JSON.parse(response.body)
    assert_equal true, data["ok"]
    assert_equal "John 3", data["reference"]
    assert_match(/loving the world/, data["prayer"])
    assert_includes data["url"], "/p/john-3"
  end

  test "prayer endpoint degrades gracefully without an AI key" do
    with_ai_result(AiChat::Result.new(ok: false, error: :no_key)) do
      get prayer_study_path(@study), params: { osis: "John", chapter: 3 }
    end
    assert_response :success
    data = JSON.parse(response.body)
    assert_equal false, data["ok"]
    assert_equal "no_key", data["error"]
  end
end
