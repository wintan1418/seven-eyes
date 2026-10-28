# Hotwire Native path configuration, fetched by the iOS and Android apps on
# launch. Changing these rules changes how the apps behave (which pages open as
# modals, where pull-to-refresh is off) without a store release.
class ConfigurationsController < ApplicationController
  allow_unauthenticated_access

  # New/edit forms slide up as modals…
  MODAL_PATTERNS = [ "/new$", "/edit$" ].freeze
  # …except signing in, signing up and password resets, which are full screens.
  FULL_SCREEN_PATTERNS = [ "^/session/new$", "^/registration/new$", "^/passwords/new$", "^/passwords/.+/edit$" ].freeze
  # Pages that scroll inside their own panes or are driven by gestures, where
  # pulling down must not reload the page: the reader, preach, live, remote.
  NO_PULL_TO_REFRESH = [ "^/read$", "^/studies/\\d+", "^/live/", "^/remote/" ].freeze

  def ios_v1
    render json: rules_for(default: {}, modal: {})
  end

  def android_v1
    render json: rules_for(default: { uri: "hotwire://fragment/web" },
                           modal: { uri: "hotwire://fragment/web/modal/sheet" })
  end

  private

  def rules_for(default:, modal:)
    {
      settings: {},
      rules: [
        { patterns: [ ".*" ], properties: { context: "default", pull_to_refresh_enabled: true, **default } },
        { patterns: MODAL_PATTERNS, properties: { context: "modal", pull_to_refresh_enabled: false, **modal } },
        { patterns: FULL_SCREEN_PATTERNS, properties: { context: "default", pull_to_refresh_enabled: false, **default } },
        { patterns: NO_PULL_TO_REFRESH, properties: { pull_to_refresh_enabled: false } }
      ]
    }
  end
end
