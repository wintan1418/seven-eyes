module ApplicationHelper
  READER_THEMES = %w[vellum candlelight paper auto].freeze
  DEFAULT_THEME = "vellum".freeze
  # Browser chrome colour per theme (the PWA status bar / mobile address bar).
  THEME_COLORS = { "vellum" => "#F4EAD2", "candlelight" => "#17120C", "paper" => "#FFFFFF" }.freeze
  # The reader's theme lives in the `ps_reader_theme` cookie. The first cut of
  # the redesign stored light/auto in the older `ps_theme` cookie for everyone,
  # which kept people on a white or dark page instead of the cream default — so
  # that cookie is ignored, except for the original UI's explicit dark choice.
  THEME_COOKIE = :ps_reader_theme
  LEGACY_COOKIE = :ps_theme

  # Who the data the device keeps for offline use belongs to (saved pages,
  # cached highlights, queued writes): an opaque per-user tag, or "guest".
  # When it changes the page wipes the previous reader's saved pages.
  def offline_owner
    return "guest" unless authenticated?
    "u-#{OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "offline-owner:#{current_user.id}")[0, 16]}"
  end

  # Rendered server-side on <body data-theme> so a Turbo visit never flashes
  # the wrong colours. Vellum (cream) is the default; "auto" is Vellum by day
  # and Candlelight when the device is in dark mode.
  def reader_theme
    value = cookies[THEME_COOKIE].to_s
    return value if READER_THEMES.include?(value)
    return "candlelight" if cookies[LEGACY_COOKIE].to_s == "candlelight"
    DEFAULT_THEME
  end

  # <meta name="theme-color"> for the current theme; for "auto" one per colour
  # scheme so the browser picks the right one itself.
  def theme_color_meta_tags
    theme = reader_theme
    if theme == "auto"
      safe_join([
        tag.meta(name: "theme-color", content: THEME_COLORS["vellum"], media: "(prefers-color-scheme: light)"),
        tag.meta(name: "theme-color", content: THEME_COLORS["candlelight"], media: "(prefers-color-scheme: dark)")
      ], "\n")
    else
      tag.meta(name: "theme-color", content: THEME_COLORS.fetch(theme))
    end
  end

  # Page title inside the iOS/Android apps, where it is shown in the native top
  # bar: just the page's own name, without the site-name suffix.
  def native_page_title(title)
    title.to_s.split(/\s[·—|-]\s/).first.presence || "BiblioRata"
  end
end
