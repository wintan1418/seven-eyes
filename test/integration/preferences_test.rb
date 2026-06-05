require "test_helper"

class PreferencesTest < ActionDispatch::IntegrationTest
  test "a signed-in user completing the tour stamps tour_completed_at" do
    sign_in_as users(:one)
    assert_nil users(:one).reload.tour_completed_at
    patch preferences_path, params: { tour_completed: "1" }
    assert_response :no_content
    assert users(:one).reload.tour_completed_at.present?
  end

  test "guests can hit preferences without error and nothing is persisted" do
    patch preferences_path, params: { tour_completed: "1" }
    assert_response :no_content
  end
end
