module ApplicationHelper
  READER_THEMES = %w[vellum candlelight paper auto].freeze
  DEFAULT_THEME = "vellum".freeze
  # Browser chrome colour per theme (the PWA status bar / mobile address bar).
  THEME_COLORS = { "vellum" => "#F4EAD2", "candlelight" => "#17120C", "paper" => "#FFFFFF" }.freeze
  # Names used by the first cut of the redesign (never released) → current names.
  THEME_ALIASES = { "light" => "paper", "dark" => "candlelight", "sepia" => "vellum" }.freeze

  # The reader's theme, from the ps_theme cookie the theme controller writes —
  # rendered server-side on <body data-theme> so a Turbo visit never flashes
  # the wrong colours. Vellum (cream) is the default; "auto" is Vellum by day
  # and Candlelight when the device is in dark mode.
  def reader_theme
    value = cookies[:ps_theme].to_s
    value = THEME_ALIASES.fetch(value, value)
    READER_THEMES.include?(value) ? value : DEFAULT_THEME
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
end
