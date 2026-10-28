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

  test "the page renders in the reader's theme from the ps_theme cookie (no flash)" do
    get root_path
    assert_select "body[data-theme=vellum]"

    cookies[:ps_reader_theme] = "candlelight"
    get root_path
    assert_select "body[data-theme=candlelight]"

    cookies[:ps_reader_theme] = ""
    cookies[:ps_theme] = "light" # left over from the first cut of the redesign
    get root_path
    assert_select "body[data-theme=vellum]"

    cookies[:ps_reader_theme] = "<script>"
    get root_path
    assert_select "body[data-theme=vellum]"
  end
end
