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
    assert_select "a.pub-open", text: /Open in BiblioRata/
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

  test "a cross-chapter slug loads both chapters with headings" do
    Verse.create!(translation: @kjv, book: @john, chapter: 4, verse_number: 1, text: "When therefore the Lord knew")
    get passage_path("john-3-17-to-4-1")
    assert_response :success
    assert_includes response.body, "condemn the world"
    assert_includes response.body, "When therefore the Lord knew"
    refute_includes response.body, "only begotten Son"
    assert_select "h3", text: /John 4/
  end

  test "a link naming a hidden translation falls back to an offered one" do
    net = Translation.create!(code: "NET", name: "NET Bible")
    Verse.create!(translation: net, book: @john, chapter: 3, verse_number: 16, text: "NET wording")
    get passage_path("john-3-16", params: { t: "NET" })
    assert_response :success
    refute_includes response.body, "NET wording"
    assert_includes response.body, "only begotten Son"
  end

  test "the passage page links to the credits page, which lists licences" do
    get passage_path("john-3-16")
    assert_select "a[href=?]", credits_path

    Translation.create!(code: "LSV", name: "Literal Standard Version", license: "cc_by_sa")
    Translation.create!(code: "NET", name: "NET Bible", license: "restricted")
    get credits_path
    assert_response :success
    assert_includes response.body, "King James Version"
    assert_includes response.body, "Covenant Press"
    assert_includes response.body, "OpenBible.info"
    assert_includes response.body, "Open Scriptures"
    refute_includes response.body, "NET Bible"
  end
end
