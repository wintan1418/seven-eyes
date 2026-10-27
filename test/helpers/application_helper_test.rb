require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "the theme follows the device until the reader picks one" do
    assert_equal "auto", reader_theme
    cookies[:ps_theme] = "dark"
    assert_equal "dark", reader_theme
    cookies[:ps_theme] = "sepia"
    assert_equal "sepia", reader_theme
  end

  test "the old two-theme cookie values map onto the new themes" do
    cookies[:ps_theme] = "candlelight"
    assert_equal "dark", reader_theme
    cookies[:ps_theme] = "vellum" # the old UI wrote this for everyone
    assert_equal "auto", reader_theme
    cookies[:ps_theme] = "<script>"
    assert_equal "auto", reader_theme
  end

  test "auto renders a theme-color per colour scheme, a chosen theme renders one" do
    html = theme_color_meta_tags
    assert_includes html, %(media="(prefers-color-scheme: dark)")
    assert_includes html, "#111113"
    cookies[:ps_theme] = "sepia"
    assert_equal %(<meta name="theme-color" content="#F7F1E3">), theme_color_meta_tags
  end
end
