require "application_system_test_case"

# The My Media page (/media): upload several pictures at once, rename one, set
# how it fills the screen by default, find it by title, delete one a service
# uses (the service keeps it) — on a laptop and on a phone.
class MyMediaPageTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @user.update!(tour_completed_at: Time.current)
  end

  teardown do
    page.driver.browser.manage.window.resize_to(1400, 1000)
    clear_offline_data
  end

  test "upload, rename, default display, search and delete" do
    sign_in
    visit media_assets_path
    assert_text "No pictures yet"

    find("input.mm-file", visible: :all).attach_file(
      [ "welcome_flyer.png", "harvest_tall.png" ].map { |f| Rails.root.join("test/fixtures/files", f).to_s }, make_visible: true)
    assert_selector ".mm-card", count: 2, wait: 15
    assert_selector ".mm-up.is-ok", count: 2
    assert_selector ".mm-storage", text: "2 pictures"
    assert_no_text "No pictures yet"

    flyer = @user.media_assets.find_by!(title: "welcome flyer")
    card = "#media_asset_#{flyer.id}"

    # Rename: saved when the field changes.
    find("#{card} input[name='title']").fill_in(with: "Welcome flyer")
    find("#{card} input[name='title']").send_keys(:enter)
    assert_selector "#{card} input[name='title'][value='Welcome flyer']"
    assert_equal "Welcome flyer", flyer.reload.title

    # Default display: Fill — the thumbnail shows it at once.
    find("#{card} .mm-seg label", text: "Fill").click
    assert_selector "#{card} .mm-thumb[data-fit='fill']"
    assert_equal "fill", flyer.reload.display["fit"]

    # The same picture again is kept once.
    find("input.mm-file", visible: :all).attach_file(Rails.root.join("test/fixtures/files/welcome_flyer.png").to_s, make_visible: true)
    assert_selector ".mm-up.is-ok", text: "Already in My Media"
    assert_selector ".mm-card", count: 2
    assert_equal 2, @user.media_assets.count

    # Search by title.
    find(".mm-search input").fill_in(with: "harv")
    assert_selector ".mm-card", count: 1, visible: true
    find(".mm-search input").fill_in(with: "nothing like it")
    assert_text "No picture has that in its title"
    find(".mm-search input").fill_in(with: "")

    # Delete one a service uses: a clear warning, and the service keeps it.
    study = @user.studies.create!(name: "Sunday")
    item = study.setlist_items.create!(SetlistItem.picture_attrs_from(flyer.reload))
    visit media_assets_path
    assert_selector "#{card} .mm-meta", text: "In 1 service"
    accept_confirm(/used in 1 service\. Those services keep showing it/) do
      find("#{card} .mm-del").click
    end
    assert_no_selector card
    assert_selector ".mm-storage", text: "1 picture"
    assert_text "Deleted “Welcome flyer” from My Media"
    assert item.reload.picture_file.attached?
    assert_nil item.media_asset_id
  end

  test "on a phone (390px): two columns, nothing wider than the screen" do
    library_picture(@user, title: "Welcome flyer")
    library_picture(@user, "harvest_tall.png", title: "Harvest")
    library_picture(@user, "giving.jpg", title: "Giving")
    sign_in
    page.driver.browser.manage.window.resize_to(390, 844)
    visit media_assets_path
    assert_selector ".mm-card", count: 3
    assert_operator page.evaluate_script("document.documentElement.scrollWidth - document.documentElement.clientWidth"), :<=, 0
    lefts = all(".mm-card").map { |c| c.evaluate_script("Math.round(this.getBoundingClientRect().left)") }.uniq
    assert_equal 2, lefts.size, "two columns on a phone"
    assert_selector ".mm-card .mm-seg label", text: "Stretch"
  end

  test "guests are asked to sign in; the menu links signed-in readers here" do
    visit media_assets_path
    assert_link "Sign in"
    assert_no_selector ".mm-grid"
    sign_in
    visit more_path
    assert_link href: media_assets_path
  end

  private

  def sign_in
    visit new_session_path
    fill_in "email_address", with: @user.email_address
    fill_in "password", with: "password"
    click_on "Sign In"
    assert_no_current_path new_session_path
  end
end
