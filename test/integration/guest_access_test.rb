require "test_helper"

class GuestAccessTest < ActionDispatch::IntegrationTest
  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    Verse.create!(translation: @kjv, book: @john, chapter: 3, verse_number: 16, text: "For God so loved the world")
  end

  test "a guest can open the workspace and create a guest study" do
    assert_difference -> { Study.where(user_id: nil).count }, 1 do
      post studies_path
    end
    study = Study.last
    assert_nil study.user_id
    follow_redirect!
    assert_response :success
    assert_select "turbo-frame.ps-pane"
  end

  test "a guest can navigate Scripture (reference change) without an account" do
    post studies_path
    study = Study.last
    patch study_pane_path(study, study.panes.first), params: { pane: { reference: "John 3:16" } }
    assert_response :success
    assert_includes response.body, "For God so loved the world"
  end

  test "a guest saving notes is blocked with 401" do
    post studies_path
    study = Study.last
    patch study_pane_path(study, study.panes.first), params: { autosave: "1", pane: { notes: "mine" } }
    assert_response :unauthorized
    assert_nil study.panes.first.reload.notes
  end

  test "a guest highlighting is blocked with 401" do
    verse = Verse.first
    post highlights_path, params: { highlight: { verse_id: verse.id, color: "ochre", char_start: 0, char_end: 3 } }, as: :json
    assert_response :unauthorized
  end

  test "a guest cannot open someone else's study" do
    post studies_path # creates my guest study (sets session)
    others = Study.create!(user: nil, name: "Other guest", pane_count: 1)
    get study_path(others)
    assert_response :not_found
  end

  test "registering claims the guest study into the new account" do
    post studies_path
    guest_study = Study.last

    assert_difference -> { User.count }, 1 do
      post registration_path, params: { email_address: "new@example.com", password: "password123", password_confirmation: "password123" }
    end
    user = User.find_by(email_address: "new@example.com")
    assert_equal user.id, guest_study.reload.user_id
    assert_redirected_to study_path(guest_study)
  end

  test "signing in claims the guest study" do
    post studies_path
    guest_study = Study.last
    post session_path, params: { email_address: users(:one).email_address, password: "password" }
    assert_equal users(:one).id, guest_study.reload.user_id
  end
end
