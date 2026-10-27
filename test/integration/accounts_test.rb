require "test_helper"

class AccountsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    @verse = Verse.create!(translation: @kjv, book: @john, chapter: 3, verse_number: 16,
                           text: "For God so loved the world")
    @study = @user.studies.create!(name: "Sunday sermon", pane_count: 1)
    @study.panes.first.update!(reference: "John 3:16", translation: @kjv, notes: "Private sermon notes")
    @highlight = @user.highlights.create!(verse: @verse, color: :sage, char_start: 4, char_end: 7, note: "God!")
  end

  test "the account page requires sign-in" do
    get account_path
    assert_redirected_to new_session_path
  end

  test "a member sees their account page with export and delete" do
    sign_in_as @user
    get account_path
    assert_response :success
    assert_includes response.body, @user.email_address
    assert_select "a[href=?]", export_account_path
    assert_select "form[action=?] input[name=password]", account_path
  end

  test "export downloads the member's studies, notes and highlights as JSON" do
    sign_in_as @user
    users(:two).studies.create!(name: "Not mine", pane_count: 1)

    get export_account_path
    assert_response :success
    assert_equal "application/json", response.media_type
    assert_match(/attachment; filename="bibliorata-export-/, response.headers["Content-Disposition"])

    data = JSON.parse(response.body)
    assert_equal @user.email_address, data.dig("account", "email_address")
    assert_equal [ "Sunday sermon" ], data["studies"].map { |s| s["name"] }
    assert_equal "Private sermon notes", data["studies"].first["panes"].first["notes"]
    hl = data["highlights"].first
    assert_equal "John 3:16", hl["reference"]
    assert_equal "God", hl["highlighted_text"]
    assert_equal "God!", hl["note"]
    assert_not_includes response.body, "password_digest"
  end

  test "deleting requires the correct password" do
    sign_in_as @user
    assert_no_difference -> { User.count } do
      delete account_path, params: { password: "wrong" }
    end
    assert_redirected_to account_path
    assert Study.exists?(@study.id)
  end

  test "deleting with the password removes the user and all their data" do
    sign_in_as @user
    IllustrationQuota.for(IllustrationQuota.key_for(@user)).reserve!
    Testimonials::Testimonial.create!(author_id: @user.id.to_s, body: "Lovely", rating: 5)
    other_study = users(:two).studies.create!(name: "Someone else's", pane_count: 1)

    assert_difference -> { User.count }, -1 do
      delete account_path, params: { password: "password" }
    end
    assert_redirected_to root_path

    assert_not Study.exists?(@study.id)
    assert_not Pane.exists?(study_id: @study.id)
    assert_not Highlight.exists?(@highlight.id)
    assert_not Session.exists?(user_id: @user.id)
    assert_not IllustrationQuota.exists?(owner_key: "u#{@user.id}")
    assert_not Testimonials::Testimonial.exists?(author_id: @user.id.to_s)
    assert Study.exists?(other_study.id), "other users' data is untouched"

    get account_path
    assert_redirected_to new_session_path, "the deleted user is signed out"
  end

  test "the legal pages are public and linked from sign-up" do
    get terms_path
    assert_response :success
    assert_includes response.body, "AI-generated content"
    get privacy_path
    assert_response :success
    assert_includes response.body, "What we store"
    get new_registration_path
    assert_select "a[href=?]", terms_path
    assert_select "a[href=?]", privacy_path
  end
end
