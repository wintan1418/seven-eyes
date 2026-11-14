require "test_helper"

class DaypartTest < ActiveSupport::TestCase
  def at(hour, min = 0) = Daypart.at(Time.find_zone(DailyWord::TIME_ZONE).local(2026, 11, 14, hour, min))

  test "dawn, midday and evening on the Lagos clock" do
    assert_equal :dawn, at(4).key
    assert_equal :dawn, at(9, 59).key
    assert_equal :day, at(10).key
    assert_equal :day, at(16, 59).key
    assert_equal :evening, at(17).key
    assert_equal :evening, at(23).key
    assert_equal :evening, at(2).key
  end

  test "the greeting follows the hour" do
    assert_equal "Good morning", at(6).greeting
    assert_equal "Good morning", at(11).greeting
    assert_equal "Good afternoon", at(12).greeting
    assert_equal "Good evening", at(19).greeting
    assert_equal "Good evening", at(1).greeting
  end

  test "it reads the time in Lagos, whatever zone it is given" do
    utc = Time.utc(2026, 11, 14, 8, 30) # 09:30 in Lagos
    assert_equal :dawn, Daypart.at(utc).key
    assert_equal 9, Daypart.at(utc).hour
    assert_equal "Midday", at(12).label
  end
end
