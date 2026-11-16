require "application_system_test_case"

# A church tester pressed Present on Home and got the app's old screens: the
# device's saved copy of the study (kept for preaching with no signal) was
# from before the last deploy, and a slow connection let the worker show it
# at once. With a network, a saved copy of an older version is never shown
# first; with none, it still opens.
class SavedPageVersionTest < ApplicationSystemTestCase
  include OfflineTestHelper

  setup do
    clear_offline_data
    @user = users(:one)
    @user.update!(tour_completed_at: Time.current, guide_dismissed_at: Time.current)
    kjv = Translation.create!(code: "KJV", name: "King James Version")
    john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    (1..3).each { |v| Verse.create!(translation: kjv, book: john, chapter: 3, verse_number: v, text: "KJV John 3:#{v}") }
    @study = @user.studies.create!(name: "Sunday", pane_count: 1, last_opened_at: 1.hour.ago)
    @study.panes.first.update!(reference: "John 3", translation: kjv)
  end

  teardown do
    go_online
    clear_offline_data
  end

  test "Present opens the current app, not a saved copy from an older version" do
    sign_in
    visit study_path(@study)
    wait_for_service_worker
    visit study_path(@study) # now through the worker: it saves the page
    wait_for_saved_page(study_path(@study))
    plant_old_copy

    # Even "Present offline" (?saved=1, which opens the saved copy first):
    # the fresh page, since this copy belongs to an older version.
    visit "#{study_path(@study)}?present=1&saved=1"
    assert_selector ".ps-root.is-preaching", wait: 10
    assert_no_selector "[data-old-copy]", visible: :all

    # The worker kept the fresh page in its place.
    assert_not old_copy_saved?, "the old copy should have been replaced"

    # No signal at all: the saved copy (whatever its version) still opens.
    plant_old_copy
    go_offline
    visit "#{study_path(@study)}?present=1&saved=1"
    assert_selector "[data-old-copy]", visible: :all, wait: 10
  end

  private

  def sign_in
    visit new_session_path
    fill_in "email_address", with: @user.email_address
    fill_in "password", with: "password"
    click_on "Sign In"
    assert_current_path root_path
  end

  # The saved page, as an older deploy would have left it: other app files.
  def plant_old_copy
    page.evaluate_async_script(<<~JS, study_path(@study))
      const [path, done] = arguments
      const key = new URL(path, location.origin).href
      caches.open("ps-pages").then(async (cache) => {
        const res = await cache.match(key)
        let html = await res.text()
        html = html.replace(/\\/assets\\/application-[0-9a-f]+\\.js/g, "/assets/application-0ldd0ld0.js")
                   .replace("<body", "<body data-old-copy")
        await cache.put(key, new Response(html, { headers: { "Content-Type": "text/html; charset=utf-8" } }))
        done(true)
      }).catch(() => done(false))
    JS
  end

  def old_copy_saved?
    Timeout.timeout(10) do
      loop do
        old = page.evaluate_async_script(<<~JS, study_path(@study))
          const [path, done] = arguments
          caches.open("ps-pages").then(c => c.match(new URL(path, location.origin).href))
            .then(r => r ? r.text() : "").then(t => done(t.includes("data-old-copy")), () => done(true))
        JS
        return false unless old
        sleep 0.2
      end
    end
  rescue Timeout::Error
    true
  end
end
