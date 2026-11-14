require "application_system_test_case"

# "Once 'Offline' shows it never goes away": inside the apps the browser's
# `online` event often never fires (data came back while the app was in the
# background) and navigator.onLine can stay false. The badge now asks the
# server when the page comes back into view (and every 15 s while shown) and
# clears as soon as it answers.
class OfflineBadgeClearsTest < ApplicationSystemTestCase
  test "the offline badge clears when the server answers, even if the browser still says offline" do
    visit root_path
    assert_selector ".ps-offline-badge", visible: :hidden

    # The device says it's offline, and keeps saying so (a stale web view).
    page.execute_script(<<~JS)
      Object.defineProperty(Navigator.prototype, "onLine", { configurable: true, get: () => false })
      window.dispatchEvent(new Event("offline"))
    JS
    assert_selector ".ps-offline-badge", visible: true

    # Back in the app: the page regains focus, checks the server, and clears.
    page.execute_script(%(window.dispatchEvent(new Event("focus"))))
    assert_selector ".ps-offline-badge", visible: :hidden, wait: 6

    # A real "offline" event brings it back.
    page.execute_script(%(window.dispatchEvent(new Event("offline"))))
    assert_selector ".ps-offline-badge", visible: true
  end
end
