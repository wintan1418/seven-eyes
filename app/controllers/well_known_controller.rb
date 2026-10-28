# Files phones fetch to trust that bibliorata.com links (shared passages, live
# follow-along QR codes, phone remotes, shared studies) may open in the
# BiblioRata app instead of the browser.
class WellKnownController < ApplicationController
  allow_unauthenticated_access

  APP_ID = "com.bibliorata.app".freeze
  # Only these paths open in the app; everything else stays in the browser.
  APP_LINK_PATHS = %w[ /p/* /live/* /remote/* /s/* ].freeze

  # SHA-256 fingerprints of the keys the Android app is signed with.
  # The upload key signs direct installs (APKs); Google Play re-signs store
  # installs with its own app-signing key.
  ANDROID_UPLOAD_KEY_SHA256 =
    "F4:44:DB:FC:2C:F2:A6:36:C9:18:82:28:13:35:5E:84:EE:9B:E9:CC:DE:80:70:2A:61:2F:2D:B7:B4:70:64:1C".freeze

  # PLACEHOLDER — add Google Play's app-signing key once the app exists in Play
  # Console (Setup → App signing → SHA-256), via ENV["ANDROID_PLAY_SIGNING_SHA256"]
  # or by adding it here. Until then, Play installs open links in the browser.
  def self.android_fingerprints
    [ ANDROID_UPLOAD_KEY_SHA256, ENV["ANDROID_PLAY_SIGNING_SHA256"].presence ].compact
  end

  # PLACEHOLDER — the Apple Developer Team ID (10 characters) goes in
  # ENV["APPLE_TEAM_ID"] once the Apple Developer account exists. Until then
  # the file is served with "TEAMID" and iOS Universal Links stay off.
  def self.apple_app_id
    "#{ENV.fetch('APPLE_TEAM_ID', 'TEAMID')}.#{APP_ID}"
  end

  def assetlinks
    expires_in 1.hour, public: true
    render json: [
      {
        relation: [ "delegate_permission/common.handle_all_urls" ],
        target: {
          namespace: "android_app",
          package_name: APP_ID,
          sha256_cert_fingerprints: self.class.android_fingerprints
        }
      }
    ]
  end

  # iOS Universal Links (served with no file extension, as JSON).
  def apple_app_site_association
    expires_in 1.hour, public: true
    render json: {
      applinks: {
        details: [
          {
            appIDs: [ self.class.apple_app_id ],
            components: APP_LINK_PATHS.map { |path| { "/" => path } }
          }
        ]
      }
    }
  end
end
