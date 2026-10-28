# Offline system tests. Chrome's DevTools offline emulation only covers the
# page itself — a service worker's own fetch() still reaches the server — so
# "no signal" is two switches thrown together:
#   • NetworkUnplug drops every connection to the test server (the browser,
#     and its service worker, see a network error, as on a dead Wi-Fi), and
#   • Network.emulateNetworkConditions makes navigator.onLine false and fires
#     the page's `offline` event, so the UI shows its offline state.
class NetworkUnplug
  class << self
    attr_accessor :unplugged
  end

  def initialize(app)
    @app = app
  end

  def call(env)
    if self.class.unplugged && env["rack.hijack"]
      io = env["rack.hijack"].call
      io.close rescue nil # rubocop:disable Style/RescueModifier
      return [ -1, {}, [] ]
    end
    @app.call(env)
  end
end

module OfflineTestHelper
  def go_offline
    NetworkUnplug.unplugged = true
    page.driver.browser.execute_cdp("Network.emulateNetworkConditions",
      offline: true, latency: 0, downloadThroughput: -1, uploadThroughput: -1)
  end

  def go_online
    NetworkUnplug.unplugged = false
    page.driver.browser.execute_cdp("Network.emulateNetworkConditions",
      offline: false, latency: 0, downloadThroughput: -1, uploadThroughput: -1)
  end

  # The service worker is installed and controls this page (so its fetches,
  # and the page saved for offline use, go through it).
  def wait_for_service_worker
    Timeout.timeout(15) do
      sleep 0.1 until page.evaluate_script("!!(navigator.serviceWorker && navigator.serviceWorker.controller)")
    end
  end

  # A visited page is saved by the worker in the background — wait for it.
  def wait_for_saved_page(path)
    Timeout.timeout(15) do
      sleep 0.1 until page.evaluate_async_script(<<~JS, path)
        const [path, done] = arguments
        caches.open("ps-pages").then(c => c.match(new URL(path, location.origin).href)).then(r => done(!!r), () => done(false))
      JS
    end
  end

  def download_bible(code)
    within(".ui-offline-row[data-code='#{code}']") do
      assert_no_text "Checking"
      find("[data-role='download']").click unless has_text?("On this device", wait: 0)
      assert_text "On this device", wait: 20
    end
  end

  # A clean origin: no service worker, saved pages, IndexedDB or cookies.
  def clear_offline_data
    origin = Capybara.current_session.server.base_url
    page.driver.browser.execute_cdp("Storage.clearDataForOrigin", origin:, storageTypes: "all")
  rescue StandardError
    nil
  end
end
