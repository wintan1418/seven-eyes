require "test_helper"

# POST /offline/prepare: the always-ready Quick Present study (so a presenter
# can start projecting with no internet) plus the recent studies the device
# keeps offline.
class QuickPresentTest < ActionDispatch::IntegrationTest
  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @web = Translation.create!(code: "WEB", name: "World English Bible")
    @user = users(:one)
  end

  test "guests are refused" do
    post offline_prepare_path
    assert_response :unauthorized
    assert_equal 0, Study.where(quick_present: true).count
  end

  test "creates the user's Quick Present study once, ready on their translation" do
    sign_in_as @user
    @user.studies.create!(name: "Romans", pane_count: 1).panes.first.update!(reference: "Rom 8", translation: @web)

    assert_difference -> { @user.studies.where(quick_present: true).count }, 1 do
      post offline_prepare_path
    end
    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    data = response.parsed_body["quick_present"]
    study = @user.studies.find_by!(quick_present: true)
    assert_equal study.id, data["id"]
    assert_equal "/studies/#{study.id}", data["url"]
    assert_equal "Quick Present", study.name
    assert_equal 1, study.pane_count
    assert_equal "John 3", study.panes.first.reference
    assert_equal({ "id" => @web.id, "code" => "WEB" }, data["translation"])

    # Idempotent: asking again returns the same study, untouched.
    study.panes.first.update!(reference: "Psalm 23")
    assert_no_difference -> { Study.count } do
      post offline_prepare_path
    end
    assert_equal study.id, response.parsed_body.dig("quick_present", "id")
    assert_equal "Psalm 23", study.panes.first.reload.reference
  end

  test "each user gets their own; a second one can't be made" do
    sign_in_as users(:two)
    post offline_prepare_path
    theirs = response.parsed_body.dig("quick_present", "id")

    sign_in_as @user
    post offline_prepare_path
    mine = response.parsed_body.dig("quick_present", "id")
    assert_not_equal theirs, mine
    assert_equal @user.id, Study.find(mine).user_id
    assert_equal @kjv.code, response.parsed_body.dig("quick_present", "translation", "code") # site default

    assert_raises(ActiveRecord::RecordNotUnique) { @user.studies.create!(name: "Another", quick_present: true) }
    assert_equal mine, QuickPresent.ensure!(@user).id
  end

  test "lists the five most recent studies, never Quick Present itself" do
    sign_in_as @user
    studies = 7.times.map { |i| @user.studies.create!(name: "Study #{i}", last_opened_at: i.hours.ago) }
    users(:two).studies.create!(name: "Not mine", last_opened_at: Time.current)

    post offline_prepare_path
    recent = response.parsed_body["recent"]
    assert_equal studies.first(5).map(&:id), recent.map { |s| s["id"] }
    assert_equal "/studies/#{studies.first.id}", recent.first["url"]
  end

  test "the Bible tab (/read) never lands on Quick Present" do
    sign_in_as @user
    reading = @user.studies.create!(name: "Reading", last_opened_at: 2.days.ago)
    QuickPresent.ensure!(@user).touch_opened!
    get read_path
    assert_redirected_to study_path(reading)
  end

  test "pages saved for offline use don't count as opening the study" do
    sign_in_as @user
    study = @user.studies.create!(name: "Old", last_opened_at: 3.days.ago)
    get study_path(study), headers: { "X-Offline-Precache" => "1" }
    assert_response :success
    assert_in_delta 3.days.ago, study.reload.last_opened_at, 5

    get study_path(study)
    assert_in_delta Time.current, study.reload.last_opened_at, 5
  end
end
