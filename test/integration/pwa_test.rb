require "test_helper"

class PwaTest < ActionDispatch::IntegrationTest
  test "manifest endpoint returns JSON with the app's identity" do
    get pwa_manifest_path(format: :json)
    assert_response :success
    data = JSON.parse(@response.body)
    assert_equal "Parallel Scripture", data["name"]
    assert_equal "standalone", data["display"]
    assert_equal "/", data["start_url"]
  end

  test "service worker endpoint serves JS with cache logic" do
    get pwa_service_worker_path, headers: { "Accept" => "text/javascript" }
    assert_response :success
    assert_match(/CACHE_VERSION/, @response.body)
    assert_match(/networkFirst/, @response.body)
  end

  test "layout links the manifest and sets the theme color" do
    get root_path
    assert_response :success
    assert_select "link[rel=manifest][href=?]", pwa_manifest_path(format: :json)
    assert_select "meta[name=theme-color]"
  end

  test "every page carries the offline-badge wrapper" do
    get root_path
    assert_select "[data-controller~=offline] .ps-offline-badge"
  end
end
