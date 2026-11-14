require "test_helper"
require_relative "test_helpers/offline_test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  include OfflineTestHelper
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ]

  # One browser at a time. The offline tests flip a process-wide network switch
  # (NetworkUnplug) and clear the origin's storage and service worker, so
  # parallel workers trip over each other (sign-ins bounce, saved pages vanish).
  # Past 50 system tests Rails would fork one worker per CPU; keep it serial
  # unless PARALLEL_WORKERS asks otherwise.
  ActiveSupport::TestCase.parallelize(workers: 1) unless ENV["PARALLEL_WORKERS"]

  # Lets offline tests cut the test server off (see OfflineTestHelper).
  Capybara.app = NetworkUnplug.new(Capybara.app) unless Capybara.app.is_a?(NetworkUnplug)
  teardown { NetworkUnplug.unplugged = false; NetworkUnplug.hanging = false }

  # Every test starts on a clean device. The app saves pages and downloads the
  # KJV by itself on any visit (lib/offline/warm.js, auto_bible.js), so one
  # test's Bible (another test's verses) mustn't leak into the next.
  setup { clear_offline_data }

  # On the study page: wait until Stimulus has connected (the theme
  # controller marks the current theme in the settings sheet on connect), so
  # a tap isn't lost on a page whose controllers haven't booted yet.
  def wait_for_reader_js
    assert_selector "[data-theme-choice-param][aria-pressed='true']", visible: :all
  end

  # Preach mode opens in the operator console on a wide window. Tests written
  # for the full-screen slide (the queue as a drawer/dock, the bottom bar, the
  # Go box) choose Focus view first — on the study page, before preaching.
  def prefer_focus_view
    page.execute_script(<<~JS)
      localStorage.setItem("ps-preach-view:" + (document.body.dataset.offlineOwner || "guest"), "focus")
    JS
  end

  # The console's first-run tour, as already seen.
  def mark_console_tour_seen
    page.execute_script(<<~JS)
      localStorage.setItem("ps-console-tour:" + (document.body.dataset.offlineOwner || "guest"), "1")
    JS
  end
end
