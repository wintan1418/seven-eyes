require "test_helper"

# The iOS and Android apps (Hotwire Native, ~/bibliorata-mobile) load these
# pages in a web view. Their user agent marks the request; the layout then
# hides the web chrome the native bars replace and exposes flags the apps read.
class HotwireNativeTest < ActionDispatch::IntegrationTest
  IOS = { "User-Agent" => "Mozilla/5.0 (iPhone) AppleWebKit/605.1.15 Hotwire Native iOS; Turbo Native iOS" }.freeze
  ANDROID = { "User-Agent" => "Mozilla/5.0 (Linux; Android 16) Chrome/140 Hotwire Native Android; Turbo Native Android" }.freeze
  BROWSER = { "User-Agent" => "Mozilla/5.0 (iPhone) AppleWebKit/605.1.15 Safari/604.1" }.freeze

  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    Verse.create!(translation: @kjv, book: @john, chapter: 3, verse_number: 16, text: "For God so loved the world")
  end

  # -- Path configuration ------------------------------------------------------

  test "ios path configuration: modals for new/edit, full screens for sign-in" do
    get "/configurations/ios_v1.json"
    assert_response :success
    assert_equal "application/json", response.media_type
    rules = response.parsed_body["rules"]
    assert_equal "default", rule_for(rules, ".*")["properties"]["context"]
    assert_equal "modal", rule_for(rules, "/new$")["properties"]["context"]
    assert_equal "default", rule_for(rules, "^/session/new$")["properties"]["context"]
    assert rules.none? { |r| r["properties"].key?("uri") }, "iOS rules carry no Android fragment URIs"
  end

  test "android path configuration names the fragment destinations" do
    get "/configurations/android_v1.json"
    assert_response :success
    rules = response.parsed_body["rules"]
    assert_equal "hotwire://fragment/web", rule_for(rules, ".*")["properties"]["uri"]
    assert_equal "hotwire://fragment/web/modal/sheet", rule_for(rules, "/new$")["properties"]["uri"]
    assert_equal "hotwire://fragment/web", rule_for(rules, "^/registration/new$")["properties"]["uri"]
  end

  test "the reader, live and remote pages turn pull-to-refresh off" do
    get "/configurations/ios_v1.json"
    rule = rule_for(response.parsed_body["rules"], "^/studies/\\d+")
    assert_equal false, rule["properties"]["pull_to_refresh_enabled"]
    %w[ ^/read$ ^/live/ ^/remote/ ].each { |p| assert_includes rule["patterns"], p }
  end

  # -- The layout inside the apps ------------------------------------------------

  test "app requests get body.hotwire-native and the signed-in flag" do
    get root_path, headers: IOS
    assert_select "body.hotwire-native[data-native-signed-in=false]"

    sign_in_as users(:one)
    get more_path, headers: ANDROID
    assert_select "body.hotwire-native[data-native-signed-in=true]"
  end

  test "browsers never get the native class" do
    get root_path, headers: BROWSER
    assert_select "body.hotwire-native", count: 0
    assert_select "body[data-native-signed-in=false]"
  end

  test "inside the apps the title drops the site-name suffix (it becomes the native header)" do
    get terms_path, headers: IOS
    assert_select "title", text: "Terms of Service"

    get terms_path, headers: BROWSER
    assert_select "title", text: "Terms of Service · BiblioRata"
  end

  test "the reader keeps its chips and verse action bar and marks the native top-bar hooks" do
    sign_in_as users(:one)
    study = users(:one).studies.create!(name: "Sunday", pane_count: 1)
    study.panes.first.update!(reference: "John 3", translation: @kjv)

    get study_path(study), headers: IOS
    assert_response :success
    assert_select "body.hotwire-native"
    assert_select ".ui-appbar .ui-chip.is-passage"
    assert_select ".ui-appbar .ui-chip.is-version"
    assert_select ".ui-actionbar[data-controller=verse-actions]"
    %w[ search theme settings tools menu sign-out ].each do |action|
      assert_select "[data-native-action='#{action}']", minimum: 1, message: "missing native hook #{action}"
    end
  end

  test "the web tour is skipped inside the apps (it points at web buttons the native bars replace)" do
    sign_in_as users(:one)
    study = users(:one).studies.create!(name: "Sunday", pane_count: 1)

    get study_path(study), headers: ANDROID
    assert_not_includes css_select(".ps-root").sole["data-controller"].split, "tour"

    get study_path(study), headers: BROWSER
    assert_includes css_select(".ps-root").sole["data-controller"].split, "tour"
  end

  test "every page has the theme hook the native theme button clicks" do
    get privacy_path, headers: ANDROID
    assert_select "[data-native-action=theme][data-action~='theme#toggle']"
  end

  # -- /read: the Bible tab -------------------------------------------------------

  test "a guest's Bible tab opens a reader at John 3 and reuses it next time" do
    assert_difference -> { Study.where(user_id: nil).count }, 1 do
      get read_path, headers: ANDROID
    end
    study = Study.where(user_id: nil).last
    assert_redirected_to study_path(study)
    assert_equal "John 3", study.panes.first.reference

    assert_no_difference -> { Study.count } do
      get read_path, headers: ANDROID
    end
    assert_redirected_to study_path(study)
    follow_redirect!
    assert_response :success
    assert_includes response.body, "For God so loved the world"
  end

  test "a signed-in reader's Bible tab returns to their latest study" do
    sign_in_as users(:one)
    older = users(:one).studies.create!(name: "Older", pane_count: 1)
    newer = users(:one).studies.create!(name: "Newer", pane_count: 1)
    older.update_columns(last_opened_at: 2.days.ago)
    newer.update_columns(last_opened_at: 1.hour.ago)

    get read_path, headers: IOS
    assert_redirected_to study_path(newer)
  end

  test "a signed-in reader with no studies gets a new one at John 3" do
    sign_in_as users(:one)
    users(:one).studies.destroy_all
    assert_difference -> { users(:one).studies.count }, 1 do
      get read_path, headers: IOS
    end
    assert_equal "John 3", users(:one).studies.recent.first.panes.first.reference
  end

  # -- /more: the More tab ----------------------------------------------------------

  test "the More tab offers sign-in to guests" do
    get more_path, headers: IOS
    assert_response :success
    assert_select "a[href=?]", new_session_path
    assert_select "a[href=?]", new_registration_path
    assert_select "[data-action~='theme#choose']", 4
  end

  test "the More tab lets a signed-in reader sign out (native hook)" do
    sign_in_as users(:one)
    get more_path, headers: IOS
    assert_response :success
    assert_select "form[action=?] [data-native-action=sign-out]", session_path
    assert_select "a[href=?]", reading_plans_path
  end

  # -- Sign in / sign up inside the apps ---------------------------------------------

  test "sign-in and sign-up forms submit with Turbo inside the apps" do
    get new_session_path, headers: IOS
    assert_response :success
    assert_select "form[action=?]", session_path
    assert_select "form[data-turbo=false]", count: 0

    get new_registration_path, headers: ANDROID
    assert_response :success
    assert_select "form[data-turbo=false]", count: 0
  end

  test "signing up in the app adopts the guest's Bible-tab study" do
    get read_path, headers: ANDROID
    guest = Study.where(user_id: nil).last

    secret = SecureRandom.hex(12)
    post registration_path, headers: ANDROID,
         params: { email_address: "app-reader@example.com", password: secret, password_confirmation: secret }
    assert_redirected_to study_path(guest)
    assert_equal "app-reader@example.com", guest.reload.user.email_address
  end

  private

  def rule_for(rules, pattern)
    rules.find { |r| r["patterns"].include?(pattern) }
  end
end
