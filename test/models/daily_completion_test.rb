require "test_helper"

class DailyCompletionTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @today = DailyWord.today_date
  end

  test "record! marks a day once; a second Amen is harmless" do
    assert DailyCompletion.record!(@user, @today)
    assert_not DailyCompletion.record!(@user, @today)
    assert_equal 1, @user.daily_completions.count
    assert DailyCompletion.done_on?(@user, @today)
    assert_not DailyCompletion.done_on?(users(:two), @today)
  end

  test "a late sync from the last few days is fine; the future and long ago are not" do
    assert DailyCompletion.record!(@user, @today - 2)
    assert_raises(ArgumentError) { DailyCompletion.record!(@user, @today + 1) }
    assert_raises(ArgumentError) { DailyCompletion.record!(@user, @today - (DailyCompletion::LATE_SYNC_DAYS + 1)) }
  end

  test "the streak counts back from today, or from yesterday while today is open" do
    assert_equal 0, DailyCompletion.status_for(@user).streak

    [ 1, 2, 3 ].each { |n| @user.daily_completions.create!(date: @today - n) }
    status = DailyCompletion.status_for(@user)
    assert_not status.done_today
    assert_equal 3, status.streak, "today not done yet doesn't break it"

    DailyCompletion.record!(@user, @today)
    status = DailyCompletion.status_for(@user)
    assert status.done_today
    assert_equal 4, status.streak
    assert_equal @today, status.dates.first
  end

  test "a missed day breaks the streak" do
    @user.daily_completions.create!(date: @today)
    @user.daily_completions.create!(date: @today - 2)
    assert_equal 1, DailyCompletion.status_for(@user).streak
    assert_equal 0, DailyCompletion.streak_from([ @today - 2 ], today: @today)
  end

  test "status is one query" do
    3.times { |n| @user.daily_completions.create!(date: @today - n) }
    queries = 0
    counter = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { DailyCompletion.status_for(@user) }
    assert_equal 1, queries
  end

  test "deleting the account deletes its days" do
    @user.daily_completions.create!(date: @today)
    assert_difference -> { DailyCompletion.count }, -1 do
      @user.destroy
    end
  end
end
