require "test_helper"

# Inside the apps, an "update available" banner when the store has a newer
# version (ANDROID_LATEST_VERSION / IOS_LATEST_VERSION, see NativeAppHelper).
class AppUpdateBannerTest < ActionDispatch::IntegrationTest
  APP = "Mozilla/5.0 (Linux; Android 16) Chrome/140 BiblioRata/%s; Hotwire Native Android; Turbo Native Android".freeze
  BROWSER = "Mozilla/5.0 (Linux; Android 16) Chrome/140 Mobile Safari/537.36".freeze

  setup do
    @previous = ENV["ANDROID_LATEST_VERSION"]
    ENV["ANDROID_LATEST_VERSION"] = "1.0.2"
  end

  teardown { ENV["ANDROID_LATEST_VERSION"] = @previous }

  def visit_as(agent, path = root_path)
    get path, headers: { "User-Agent" => agent }
    assert_response :success
  end

  test "an older app version sees the banner, hidden until its controller checks the dismissal" do
    visit_as format(APP, "1.0.1")
    assert_select ".ui-app-update[hidden][data-controller=app-update][data-app-update-version-value='1.0.2']" do
      assert_select ".ui-app-update-text", text: /BiblioRata 1\.0\.2 is out/
      assert_select "a.ui-app-update-action[href=?]", "https://play.google.com/store/apps/details?id=com.bibliorata.app", text: "Update"
      assert_select "button.ui-app-update-close[aria-label='Not now'][data-action='app-update#dismiss']"
    end
  end

  test "the banner shows on other pages too" do
    visit_as format(APP, "1.0.1"), new_session_path
    assert_select ".ui-app-update"
  end

  test "the latest version and the website see no banner" do
    visit_as format(APP, "1.0.2")
    assert_select ".ui-app-update", false
    visit_as BROWSER
    assert_select ".ui-app-update", false
  end

  test "no banner until the latest version is set" do
    ENV.delete("ANDROID_LATEST_VERSION")
    visit_as format(APP, "1.0.1")
    assert_select ".ui-app-update", false
  end
end
