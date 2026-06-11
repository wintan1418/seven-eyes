require "test_helper"

class QuickFindTest < ActionDispatch::IntegrationTest
  def owner_study
    sign_in_as users(:one)
    users(:one).studies.create!(name: "Sunday", pane_count: 1)
  end

  test "a blank query is refused without touching a provider" do
    study = owner_study
    get quick_find_study_path(study, q: "  ")
    assert_response :success
    data = JSON.parse(response.body)
    refute data["ok"]
    assert_equal "blank", data["error"]
  end

  test "someone else's study is not reachable" do
    study = users(:two).studies.create!(name: "Private", pane_count: 1)
    sign_in_as users(:one)
    get quick_find_study_path(study, q: "the prodigal son")
    assert_response :not_found
  end
end
