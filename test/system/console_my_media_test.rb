require "application_system_test_case"

# My Media in the operator console (Pictures → My Media): the pastor's own
# picture library, on any computer they sign in on. Search, preview, add to
# the service, go live, and upload straight into the library.
class ConsoleMyMediaTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @user.update!(tour_completed_at: Time.current)
    kjv = Translation.create!(code: "KJV", name: "King James Version")
    john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    Verse.create!(translation: kjv, book: john, chapter: 3, verse_number: 16, text: "For God so loved the world")
    @study = @user.studies.create!(name: "Sunday Service", pane_count: 1)
    @study.panes.first.update!(reference: "John 3:16", translation: kjv)
    @flyer = library_picture(@user, title: "Welcome flyer")
    @flyer.update!(display: { fit: "fill", zoom: 100 })
    @harvest = library_picture(@user, "harvest_tall.png", title: "Harvest Sunday")
    library_picture(users(:two), "giving.jpg", title: "Not mine")
  end

  teardown { clear_offline_data }

  test "pick from My Media: preview, add to the service, go live in its default mode; upload into the library" do
    sign_in
    visit study_path(@study)
    wait_for_reader_js
    mark_console_tour_seen
    find(".ui-appbar button[data-action~='presentation#start']").click
    assert_selector ".ps-root.is-console"

    find(".cx-tab[data-tab='media']").click
    find(".cx-pbank-views [data-view='library']").click
    within("[data-console-media-target='grid']") do
      assert_selector ".cx-pcard", count: 2
      assert_text "Welcome flyer"
      assert_text "Harvest Sunday"
      assert_no_text "Not mine"
    end

    # Search by title.
    find(".cx-pbank-search").fill_in(with: "welc")
    assert_selector "[data-console-media-target='grid'] .cx-pcard", count: 1
    assert_selector "[data-console-media-target='grid'] .cx-pcard .meta", text: /fill/i

    # Click → Preview only; the big screen doesn't change.
    find("[data-console-media-target='grid'] .cx-pcard .pick").click
    assert_selector ".cx-mini[data-kind='picture'] .cx-mini-img[data-fit='fill'] img", visible: :all
    assert_selector "[data-preview-target='previewLabel']", text: "Welcome flyer"
    assert_no_selector ".ps-root.is-slide"

    # + Add to service: it joins the queue, synced to the server by library id.
    click_on "+ Add to service"
    assert_selector ".ps-setlist-items .ps-setlist-item.kind-picture", text: "Welcome flyer"
    assert_selector "[data-console-media-target='grid'] .cx-pcard.is-in-service"
    item = wait_for { @study.setlist_items.picture.first }
    assert_equal @flyer, item.media_asset
    assert_equal({ "fit" => "fill", "zoom" => 100 }, item.data)
    assert_equal @flyer.file.blob, item.picture_file.blob

    # Go live: the picture fills the screen the way the library says.
    find("button[data-action='console-media#liveSelected']").click
    assert_selector ".ps-root.is-slide .ps-preach-slide.is-picture .slide-img[data-fit='fill'] img", visible: :all

    # Upload straight into the library, and (ticked) into the service too.
    find(".cx-pbank-search").fill_in(with: "")
    find("[data-console-media-target='upload']", visible: :all).attach_file(Rails.root.join("test/fixtures/files/giving.jpg"), make_visible: true)
    assert_selector "[data-console-media-target='grid'] .cx-pcard", count: 3
    assert_selector "[data-console-media-target='status']", text: "Added 1 picture to My Media and this service"
    assert_selector ".ps-setlist-items .ps-setlist-item.kind-picture", count: 2
    assert_equal 3, @user.media_assets.count
    assert_equal 1, users(:two).media_assets.count, "the same file in someone else's library stays theirs"
  end

  private

  def sign_in
    visit new_session_path
    fill_in "email_address", with: @user.email_address
    fill_in "password", with: "password"
    click_on "Sign In"
    assert_no_current_path new_session_path
  end

  def wait_for(timeout: 10)
    Timeout.timeout(timeout) do
      loop do
        value = yield
        return value if value
        sleep 0.1
      end
    end
  end
end
