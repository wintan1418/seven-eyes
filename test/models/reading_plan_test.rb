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

  test "deleting the plan's study clears study_id instead of leaving a dangling id" do
    study = @user.studies.create!(name: "Plan study", pane_count: 1)
    @plan.update!(study:)
    study.destroy
    assert_nil @plan.reload.study_id
  end

  test "pane_references combines consecutive chapters only when they don't fit" do
    day = @plan.plan_days.create!(day_number: 9, refs: "Gen 1, Gen 2, Gen 3")
    assert_equal [ "Gen 1", "Gen 2", "Gen 3" ], day.pane_references(4)

    day.update!(refs: "Gen 1, Gen 2, Gen 3, Ps 1, Ps 2, Matt 5, Matt 6")
    assert_equal [ "Genesis 1-3", "Psalms 1-2", "Matthew 5-6" ], day.pane_references(4)

    day.update!(refs: "Gen 1, Gen 3, Ps 1, Matt 1, Mark 1")
    assert_equal [ "Gen 1", "Gen 3", "Ps 1", "Matt 1", "Mark 1" ], day.pane_references(4),
                 "non-consecutive chapters stay separate (the caller reports the overflow)"
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
