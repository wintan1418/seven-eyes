module ApplicationHelper
  READER_THEMES = %w[light dark sepia].freeze
  # Browser chrome colour per theme (the PWA status bar / mobile address bar).
  THEME_COLORS = { "light" => "#FFFFFF", "dark" => "#111113", "sepia" => "#F7F1E3" }.freeze

  # The reader's theme, from the ps_theme cookie the theme controller writes —
  # rendered server-side on <body data-theme> so a Turbo visit never flashes
  # the wrong colours. "auto" follows the device (prefers-color-scheme).
  # The old two-theme UI wrote "vellum" for everyone (its default) and
  # "candlelight" for its dark theme: those map to auto and dark.
  def reader_theme
    value = cookies[:ps_theme].to_s
    return "dark" if value == "candlelight"
    READER_THEMES.include?(value) ? value : "auto"
  end

  # <meta name="theme-color"> for the current theme; for "auto" one per colour
  # scheme so the browser picks the right one itself.
  def theme_color_meta_tags
    theme = reader_theme
    if theme == "auto"
      safe_join([
        tag.meta(name: "theme-color", content: THEME_COLORS["light"], media: "(prefers-color-scheme: light)"),
        tag.meta(name: "theme-color", content: THEME_COLORS["dark"], media: "(prefers-color-scheme: dark)")
      ], "\n")
    else
      tag.meta(name: "theme-color", content: THEME_COLORS.fetch(theme))
    end
  end
end
