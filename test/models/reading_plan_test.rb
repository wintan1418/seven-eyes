require "test_helper"

class ReadingPlanTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @plan = @user.reading_plans.create!(name: "Test", start_date: Date.current - 4.days)
    (1..5).each { |n| @plan.plan_days.create!(day_number: n, refs: "Ps #{n}") }
  end

  test "day_for maps a date to the plan day_number" do
    assert_equal 1, @plan.day_for(@plan.start_date)
    assert_equal 5, @plan.day_for(@plan.start_date + 4.days)
  end

  test "current_streak counts consecutive completed days back from today" do
    days = @plan.plan_days.order(:day_number)
    days[0].create_completion!
    days[1].create_completion!
    days[3].create_completion!
    days[4].create_completion! # today

    # Streak counts back from today: day5 done, day4 done, day3 NOT done → streak breaks.
    assert_equal 2, @plan.current_streak
    assert_equal 2, @plan.longest_streak # also 2 from the earlier pair
  end

  test "destroying a plan removes its days and completions" do
    @plan.plan_days.first.create_completion!
    assert_difference -> { PlanDay.count }, -5 do
      assert_difference -> { PlanCompletion.count }, -1 do
        @plan.destroy
      end
    end
  end
end
