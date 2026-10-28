require "test_helper"

# Phones fetch these before letting bibliorata.com links (shared passages,
# live follow-along QR codes, remotes, shared studies) open in the apps.
class WellKnownTest < ActionDispatch::IntegrationTest
  test "assetlinks.json names the Android app and its upload key" do
    get "/.well-known/assetlinks.json"

    assert_response :success
    assert_equal "application/json", response.media_type
    statement = response.parsed_body.sole
    assert_equal [ "delegate_permission/common.handle_all_urls" ], statement["relation"]
    assert_equal "com.bibliorata.app", statement["target"]["package_name"]
    assert_equal [ WellKnownController::ANDROID_UPLOAD_KEY_SHA256 ], statement["target"]["sha256_cert_fingerprints"]
  end

  test "the Play app-signing key is added from the environment once known" do
    with_env("ANDROID_PLAY_SIGNING_SHA256" => "AA:BB") do
      get "/.well-known/assetlinks.json"
      assert_includes response.parsed_body.sole["target"]["sha256_cert_fingerprints"], "AA:BB"
    end
  end

  test "apple-app-site-association opens only the shareable paths, at both locations" do
    [ "/.well-known/apple-app-site-association", "/apple-app-site-association" ].each do |path|
      get path
      assert_response :success
      assert_equal "application/json", response.media_type
      details = response.parsed_body.dig("applinks", "details").sole
      assert_equal [ "TEAMID.com.bibliorata.app" ], details["appIDs"]
      assert_equal %w[ /p/* /live/* /remote/* /s/* ], details["components"].map { |c| c["/"] }
    end
  end

  test "the Apple team id comes from the environment" do
    with_env("APPLE_TEAM_ID" => "ABCDE12345") do
      get "/.well-known/apple-app-site-association"
      assert_equal [ "ABCDE12345.com.bibliorata.app" ], response.parsed_body.dig("applinks", "details").sole["appIDs"]
    end
  end

  private

  def with_env(vars)
    old = vars.keys.index_with { |k| ENV[k] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    old.each { |k, v| ENV[k] = v }
  end
end
