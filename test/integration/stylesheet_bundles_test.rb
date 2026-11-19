require "test_helper"

# Two CSS bundles (see application.tailwind.css / study.tailwind.css): most
# pages get application.css; the pages that can present get study.css, which
# holds the preach / projector / console layer. Never both on one page.
class StylesheetBundlesTest < ActionDispatch::IntegrationTest
  def bundles
    css_select("link[rel=stylesheet]").map { |l| l["href"][%r{/assets/(application|study)-}, 1] }.compact
  end

  test "home and the other pages get application.css" do
    [ root_path, search_path, guide_path ].each do |path|
      get path
      assert_response :success
      assert_equal [ "application" ], bundles, path
    end
  end

  test "the reader (and its projector window) gets study.css" do
    get read_path
    follow_redirect!
    assert_response :success
    assert_equal [ "study" ], bundles
    get request.path, params: { output: 1 }
    assert_equal [ "study" ], bundles
  end

  test "What's new shows the projector mock-ups, so it gets study.css" do
    get whats_new_path
    assert_equal [ "study" ], bundles
  end

  test "the service worker knows both bundles (offline pages and the offline reader)" do
    get pwa_service_worker_path(format: :js)
    assert_includes response.body, ActionController::Base.helpers.asset_path("application.css")
    assert_includes response.body, ActionController::Base.helpers.asset_path("study.css")
  end
end
