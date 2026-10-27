require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ]

  # On the study page: wait until Stimulus has connected (the theme
  # controller marks the current theme in the settings sheet on connect), so
  # a tap isn't lost on a page whose controllers haven't booted yet.
  def wait_for_reader_js
    assert_selector "[data-theme-choice-param][aria-pressed='true']", visible: :all
  end
end
