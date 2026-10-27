require "test_helper"

class PwaTest < ActionDispatch::IntegrationTest
  test "manifest endpoint returns JSON with the app's identity" do
    get pwa_manifest_path(format: :json)
    assert_response :success
    data = JSON.parse(@response.body)
    assert_equal "BiblioRata", data["name"]
    assert_equal "standalone", data["display"]
    assert_equal "/", data["start_url"]
  end

  test "service worker endpoint serves JS with cache logic" do
    get pwa_service_worker_path, headers: { "Accept" => "text/javascript" }
    assert_response :success
    assert_match(/CACHE_VERSION/, @response.body)
    assert_match(/networkFirst/, @response.body)
  end

  test "service worker cache version follows the deployed asset digests" do
    get pwa_service_worker_path, headers: { "Accept" => "text/javascript" }
    assert_match(/const CACHE_VERSION = "ps-[0-9a-f]{12}"/, @response.body)
    assert_no_match(/<%/, @response.body)
  end

  test "service worker only caches public passage pages, skips redirects, clears on sign-out" do
    get pwa_service_worker_path, headers: { "Accept" => "text/javascript" }
    body = @response.body
    assert_includes body, %q(const PUBLIC_PAGE = /^\/p\/[^/]+\/?$/)
    assert_includes body, "!response.redirected"
    assert_includes body, %q("clear-caches")
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
