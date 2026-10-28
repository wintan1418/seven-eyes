require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "vellum (cream) is the default until the reader picks a theme" do
    assert_equal "vellum", reader_theme
    %w[candlelight paper auto vellum].each do |theme|
      cookies[:ps_theme] = theme
      assert_equal theme, reader_theme
    end
  end

  test "first-cut redesign names map onto the current themes; junk falls back to vellum" do
    { "dark" => "candlelight", "light" => "paper", "sepia" => "vellum", "<script>" => "vellum" }.each do |cookie, theme|
      cookies[:ps_theme] = cookie
      assert_equal theme, reader_theme
    end
  end

  test "auto renders a theme-color per colour scheme, a chosen theme renders one" do
    cookies[:ps_theme] = "auto"
    html = theme_color_meta_tags
    assert_includes html, %(media="(prefers-color-scheme: dark)")
    assert_includes html, "#17120C"
    cookies.delete(:ps_theme)
    assert_equal %(<meta name="theme-color" content="#F4EAD2">), theme_color_meta_tags
  end
end
