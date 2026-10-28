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

  test "service worker keeps public passages and the reader's own pages, skips redirects, clears on sign-out" do
    get pwa_service_worker_path, headers: { "Accept" => "text/javascript" }
    body = @response.body
    assert_includes body, %q(PUBLIC_PAGE = /^\/p\/[^/]+\/?$/)
    assert_includes body, %q(STUDY_PAGE = /^\/studies\/\d+$/)
    assert_includes body, "!response.redirected"
    assert_includes body, %q("clear-caches")
  end

  test "service worker renders panes offline and answers the preach Go box offline" do
    get pwa_service_worker_path, headers: { "Accept" => "text/javascript" }
    body = @response.body
    assert_includes body, "X-Offline-Pane"
    assert_includes body, "/reference_check"
    assert_includes body, "renderOfflinePane"
    assert_includes body, %q(self.PS_SW = { version: CACHE_VERSION)
    assert_no_match(/^export /, body, "the inlined bundle must be a classic script")
    assert_no_match(/sourceMappingURL/, body)
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
