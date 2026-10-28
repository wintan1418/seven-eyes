require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "vellum (cream) is the default until the reader picks a theme" do
    assert_equal "vellum", reader_theme
    %w[candlelight paper auto vellum].each do |theme|
      cookies[:ps_reader_theme] = theme
      assert_equal theme, reader_theme
    end
  end

  test "first-cut redesign values in the old cookie no longer override the cream default" do
    %w[light auto dark sepia vellum <script>].each do |old|
      cookies[:ps_theme] = old
      assert_equal "vellum", reader_theme, "old ps_theme=#{old}"
    end
  end

  test "the original UI's explicit dark choice carries over" do
    cookies[:ps_theme] = "candlelight"
    assert_equal "candlelight", reader_theme
    cookies[:ps_reader_theme] = "paper" # a choice made in the new UI wins
    assert_equal "paper", reader_theme
  end

  test "auto renders a theme-color per colour scheme, a chosen theme renders one" do
    cookies[:ps_reader_theme] = "auto"
    html = theme_color_meta_tags
    assert_includes html, %(media="(prefers-color-scheme: dark)")
    assert_includes html, "#17120C"
    cookies.delete(:ps_reader_theme)
    assert_equal %(<meta name="theme-color" content="#F4EAD2">), theme_color_meta_tags
  end
end
