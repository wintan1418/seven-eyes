require "test_helper"

class NativeAppHelperTest < ActionView::TestCase
  ANDROID = "Mozilla/5.0 (Linux; Android 16) Chrome/140 BiblioRata/%s; Hotwire Native Android; Turbo Native Android".freeze
  ANDROID_FIRST = "Mozilla/5.0 (Linux; Android 16) Chrome/140 Hotwire Native Android; Turbo Native Android".freeze
  IOS = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 BiblioRata/%s; Hotwire Native iOS; Turbo Native iOS".freeze
  BROWSER = "Mozilla/5.0 (Linux; Android 16) Chrome/140 Mobile Safari/537.36".freeze
  ENV_KEYS = %w[ANDROID_LATEST_VERSION IOS_LATEST_VERSION IOS_STORE_URL].freeze

  setup { @saved_env = ENV.to_h.slice(*ENV_KEYS) }
  teardown { ENV_KEYS.each { |k| ENV[k] = @saved_env[k] } }

  def with_env(values)
    ENV_KEYS.each { |k| ENV[k] = values[k] }
    yield
  end

  def as(agent) = request.user_agent = agent

  test "platform and version come from the app's user agent" do
    as format(ANDROID, "1.0.7")
    assert_equal :android, native_app_platform
    assert_equal Gem::Version.new("1.0.7"), native_app_version

    as format(IOS, "1.2")
    assert_equal :ios, native_app_platform
    assert_equal Gem::Version.new("1.2"), native_app_version
  end

  test "an app build without a version counts as 1.0.0" do
    as ANDROID_FIRST
    assert_equal Gem::Version.new("1.0.0"), native_app_version
  end

  test "a browser is not the app" do
    as BROWSER
    assert_nil native_app_platform
    assert_nil native_app_version
    with_env("ANDROID_LATEST_VERSION" => "9.9.9") { assert_nil native_app_update }
  end

  test "an older android app gets the update with the play store link" do
    as format(ANDROID, "1.0.1")
    with_env("ANDROID_LATEST_VERSION" => "1.0.2") do
      update = native_app_update
      assert_equal :android, update.platform
      assert_equal "1.0.2", update.latest_version
      assert_equal "https://play.google.com/store/apps/details?id=com.bibliorata.app", update.store_url
    end
  end

  test "no banner on the latest or a newer version" do
    with_env("ANDROID_LATEST_VERSION" => "1.0.2") do
      as format(ANDROID, "1.0.2")
      assert_nil native_app_update
      as format(ANDROID, "1.0.10")
      assert_nil native_app_update
    end
  end

  test "versions compare numerically, not as text" do
    as format(ANDROID, "1.0.9")
    with_env("ANDROID_LATEST_VERSION" => "1.0.10") { assert native_app_update }
  end

  test "no banner when the latest version is unset or invalid" do
    as format(ANDROID, "1.0.0")
    with_env({}) { assert_nil native_app_update }
    [ "", "  ", "latest", "1.0.2; drop", "v1.0.2" ].each do |bad|
      with_env("ANDROID_LATEST_VERSION" => bad) { assert_nil native_app_update, "ANDROID_LATEST_VERSION=#{bad.inspect}" }
    end
    with_env("ANDROID_LATEST_VERSION" => " 1.0.2 ") { assert native_app_update }
  end

  test "android settings never trigger the ios banner and the reverse" do
    as format(IOS, "1.0.0")
    with_env("ANDROID_LATEST_VERSION" => "2.0.0", "IOS_STORE_URL" => "https://apps.apple.com/app/id1") do
      assert_nil native_app_update
    end
    as format(ANDROID, "1.0.0")
    with_env("IOS_LATEST_VERSION" => "2.0.0", "IOS_STORE_URL" => "https://apps.apple.com/app/id1") do
      assert_nil native_app_update
    end
  end

  test "ios needs both its latest version and its store link" do
    as format(IOS, "1.0.0")
    with_env("IOS_LATEST_VERSION" => "1.0.1") { assert_nil native_app_update }
    with_env("IOS_LATEST_VERSION" => "1.0.1", "IOS_STORE_URL" => "https://apps.apple.com/app/id1") do
      update = native_app_update
      assert_equal :ios, update.platform
      assert_equal "https://apps.apple.com/app/id1", update.store_url
    end
  end
end
