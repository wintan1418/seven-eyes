require "application_system_test_case"

# A service's pictures with no internet: "Get ready for Sunday" and the
# console's "Save for offline" put them on the device (the service worker's
# ps-media cache), so with the venue's Wi-Fi gone they still go on the
# projector — the service's own pictures and any from My Media.
class OfflinePicturesTest < ApplicationSystemTestCase
  include OfflineTestHelper

  setup do
    clear_offline_data
    @user = users(:one)
    @user.update!(tour_completed_at: Time.current)
    kjv = Translation.create!(code: "KJV", name: "King James Version")
    john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    (1..3).each { |v| Verse.create!(translation: kjv, book: john, chapter: 3, verse_number: v, text: "KJV John 3:#{v}") }
    @study = @user.studies.create!(name: "Sunday Service", pane_count: 1)
    @study.panes.first.update!(reference: "John 3", translation: kjv)
    @flyer = library_picture(@user, title: "Welcome flyer")
    @study.setlist_items.create!(SetlistItem.picture_attrs_from(@flyer))
    @giving = library_picture(@user, "giving.jpg", title: "Giving") # in My Media only
  end

  teardown do
    go_online
    clear_offline_data
  end

  test "saved for offline, the pictures still project with no connection" do
    sign_in
    visit study_path(@study)
    wait_for_service_worker
    wait_for_reader_js
    mark_console_tour_seen

    # Get ready for Sunday saves the service's pictures with everything else.
    find(".ui-appbar [data-sheets-id-param='more']").click
    find(".ui-more-sheet [data-sunday-prepare]").click
    within(".ui-sunday") do
      assert_selector "li.is-ok", text: "1 picture saved on this device", wait: 20
      assert_selector "li.is-ok", text: /projector and stage screens saved/i, wait: 20
    end
    find(".ps-setlist-host .ps-drawer-head .close").click if has_selector?(".ps-setlist-host.is-open .ps-drawer-head .close", wait: 0)

    # The console says what is on the device; My Media saves the rest.
    find(".ui-appbar button[data-action~='presentation#start']").click
    assert_selector ".ps-root.is-console"
    find(".cx-tab[data-tab='media']").click
    assert_selector "[data-console-media-target='offlineText']", text: "All 1 picture in this service available offline", wait: 15
    find(".cx-pbank-views [data-view='library']").click
    assert_selector "[data-console-media-target='grid'] .cx-pcard", count: 2
    assert_selector "[data-console-media-target='offlineText']", text: "1 of 2 pictures in My Media on this device"
    click_on "⤓ Save for offline"
    assert_selector "[data-console-media-target='offlineText']", text: "All 2 pictures in My Media available offline", wait: 15
    assert_selector "[data-console-media-target='grid'] .cx-pcard.is-on-device", count: 2

    go_offline

    # The service worker answers both pictures from the device (no-store: not the browser's cache).
    [ @flyer.media_url, @giving.media_url ].each do |url|
      answer = page.evaluate_async_script(<<~JS, url)
        const [url, done] = arguments
        fetch(url, { cache: "no-store" }).then(r => r.blob().then(b => done([r.status, b.type, b.size])), e => done(String(e)))
      JS
      assert_equal 200, answer[0], "#{url} offline: #{answer.inspect}"
      assert_match %r{\Aimage/}, answer[1]
    end

    # The projector window, opened offline, shows the service's picture...
    operator = current_window
    projector = open_new_window
    within_window(projector) do
      visit "#{study_path(@study)}?output=1"
      assert_selector ".ps-root.is-output"
    end
    switch_to_window(operator)
    find(".ps-setlist-item.kind-picture .present").double_click
    within_window(projector) { assert_picture_on_screen(@flyer) }

    # ...and one from My Media, put up from the library view.
    switch_to_window(operator)
    find("[data-console-media-target='grid'] .cx-pcard", text: "Giving").find(".pick").double_click
    within_window(projector) { assert_picture_on_screen(@giving) }
  end

  private

  def assert_picture_on_screen(asset)
    assert_selector ".ps-root.is-slide .ps-preach-slide.is-picture img[src='#{asset.media_url}']", visible: :all, wait: 10
    Timeout.timeout(10) do
      sleep 0.1 until page.evaluate_script(
        "(i => !!i && i.complete && i.naturalWidth > 0)(document.querySelector('.ps-preach-slide.is-picture img'))")
    end
  end

  def sign_in
    visit new_session_path
    fill_in "email_address", with: @user.email_address
    fill_in "password", with: "password"
    click_on "Sign In"
    assert_no_current_path new_session_path
  end
end
