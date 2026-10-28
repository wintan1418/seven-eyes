# The iOS/Android apps (Hotwire Native, ~/bibliorata-mobile) put their version
# in the user agent: "BiblioRata/1.0.2; … Hotwire Native Android". When the
# store has a newer one, the layout shows a small "update available" banner.
#
# Set in the environment (Hatchbox) once a release has reached the store:
#   ANDROID_LATEST_VERSION  e.g. "1.0.2"  (unset → no banner)
#   IOS_LATEST_VERSION      e.g. "1.0.0"  (unset → no banner)
#   IOS_STORE_URL           App Store link (unset → no banner on iOS)
module NativeAppHelper
  NATIVE_APP_UA = /(?:Turbo|Hotwire) Native/
  APP_VERSION_UA = %r{BiblioRata/(\d+(?:\.\d+)*)}
  # The first builds sent no version.
  FIRST_APP_VERSION = "1.0.0".freeze
  ANDROID_STORE_URL = "https://play.google.com/store/apps/details?id=com.bibliorata.app".freeze

  NativeAppUpdate = Data.define(:platform, :latest_version, :store_url)

  # :android / :ios inside the apps, nil in a browser. Uses the user agent only
  # (not the ps_native_app cookie): the version comes from the same header.
  def native_app_platform
    agent = request.user_agent.to_s
    return unless agent.match?(NATIVE_APP_UA)

    if agent.include?("Android") then :android
    elsif agent.match?(/iPhone|iPad|iOS/) then :ios
    end
  end

  def native_app_version
    return unless native_app_platform

    Gem::Version.new(request.user_agent.to_s[APP_VERSION_UA, 1] || FIRST_APP_VERSION)
  end

  # The newest version in the store for this platform, or nil when unset/invalid.
  def native_app_latest_version(platform = native_app_platform)
    value = ENV["#{platform.to_s.upcase}_LATEST_VERSION"].to_s.strip if platform
    Gem::Version.new(value) if value.present? && Gem::Version.correct?(value)
  end

  def native_app_store_url(platform = native_app_platform)
    case platform
    when :android then ANDROID_STORE_URL
    when :ios then ENV["IOS_STORE_URL"].presence
    end
  end

  # What the update banner needs, or nil when there is nothing to show.
  def native_app_update
    platform = native_app_platform or return
    latest = native_app_latest_version(platform) or return
    store_url = native_app_store_url(platform) or return
    return unless native_app_version < latest

    NativeAppUpdate.new(platform:, latest_version: latest.to_s, store_url:)
  end
end
