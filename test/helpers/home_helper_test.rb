require "test_helper"

class HomeHelperTest < ActionView::TestCase
  test "the greeting follows the clock in Lagos" do
    lagos = ActiveSupport::TimeZone[DailyWord::TIME_ZONE]
    assert_equal "Good morning", home_greeting(lagos.local(2026, 11, 14, 7))
    assert_equal "Good afternoon", home_greeting(lagos.local(2026, 11, 14, 13))
    assert_equal "Good evening", home_greeting(lagos.local(2026, 11, 14, 20))
    assert_equal "Good evening", home_greeting(lagos.local(2026, 11, 14, 1))
    # 06:30 UTC is 07:30 in Lagos.
    assert_equal "Good morning", home_greeting(Time.utc(2026, 11, 14, 6, 30))
  end

  test "the Continue reading mark is the book's short code" do
    assert_equal "Rom", home_book_mark("Romans 8")
    assert_equal "1 Cor", home_book_mark("1 Corinthians 13")
    assert_nil home_book_mark("zzz")
    assert_nil home_book_mark(nil)
  end

  test "the progress ring draws the fraction" do
    ring = home_progress_ring(0.5, size: 64, stroke: 6)
    assert_includes ring, "hm-ring-fill"
    assert_match(/stroke-dasharray="91.11 182.21"/, ring)
  end
end
