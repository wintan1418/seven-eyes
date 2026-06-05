require "test_helper"

class PassagesTest < ActionDispatch::IntegrationTest
  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    Verse.create!(translation: @kjv, book: @john, chapter: 3, verse_number: 16,
                  text: "For God so loved the world, that he gave his only begotten Son")
    Verse.create!(translation: @kjv, book: @john, chapter: 3, verse_number: 17,
                  text: "For God sent not his Son into the world to condemn the world")
  end

  test "a guest can view a shared verse page with Open-Graph tags" do
    get passage_path("john-3-16")
    assert_response :success
    assert_includes response.body, "only begotten Son"
    assert_includes response.body, "John 3:16"
    assert_select "meta[property='og:title']"
    assert_select "meta[property='og:url'][content=?]", passage_url("john-3-16")
    assert_select "meta[name='twitter:card']"
    assert_select "a.cta", text: /Open in Parallel Scripture/
  end

  test "a whole-chapter page shows multiple verses" do
    get passage_path("john-3")
    assert_response :success
    assert_includes response.body, "only begotten Son"
    assert_includes response.body, "condemn the world"
  end

  test "an unreadable slug renders a not-found page" do
    get passage_path("not-a-book-9")
    assert_response :not_found
    assert_includes response.body, "Passage not found"
  end

  test "the prayer page still renders the passage when no AI key is configured" do
    get passage_path("john-3", params: { prayer: 1 })
    assert_response :success
    assert_includes response.body, "only begotten Son"
  end

  test "Open in app creates a guest study at the passage and redirects" do
    assert_difference -> { Study.count }, 1 do
      get open_passage_path("john-3-16", params: { t: "KJV" })
    end
    study = Study.last
    assert_redirected_to study_path(study)
    assert_equal "John 3:16", study.panes.first.reference
    assert_equal @kjv.id, study.panes.first.translation_id
  end

  test "Open in app reuses a guest's existing session study" do
    get open_passage_path("john-3-16")           # creates + remembers the guest study
    first = Study.last
    assert_no_difference -> { Study.count } do
      get open_passage_path("john-3")             # same browser session reuses it
    end
    assert_equal first.id, Study.last.id
    assert_equal "John 3", first.reload.panes.first.reference
  end

  test "Open in app puts the passage in the signed-in user's account" do
    sign_in_as users(:one)
    assert_difference -> { users(:one).studies.count }, 1 do
      get open_passage_path("john-3-16")
    end
    assert_equal users(:one).id, Study.last.user_id
  end
end
