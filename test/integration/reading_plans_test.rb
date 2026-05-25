require "test_helper"

class ReadingPlansTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
  end

  test "index renders" do
    get reading_plans_path
    assert_response :success
  end

  test "creating a plan with the book template populates days" do
    assert_difference -> { ReadingPlan.count }, 1 do
      post reading_plans_path, params: { reading_plan: {
        name: "John in a week", start_date: Date.current.iso8601,
        template: "book", book: "John", chapters_per_day: 3
      } }
    end
    plan = ReadingPlan.last
    assert_equal 7, plan.plan_days.count
    assert_equal "John 1, John 2, John 3", plan.plan_days.ordered.first.refs
  end

  test "marking a day done creates a completion" do
    plan = users(:one).reading_plans.create!(name: "X", start_date: Date.current)
    day = plan.plan_days.create!(day_number: 1, refs: "Ps 23")

    assert_difference -> { PlanCompletion.count }, 1 do
      post complete_reading_plan_plan_day_path(plan, day)
    end
    assert_response :success
    assert day.reload.completed?
  end

  test "undoing a completion removes it" do
    plan = users(:one).reading_plans.create!(name: "X", start_date: Date.current)
    day = plan.plan_days.create!(day_number: 1, refs: "Ps 23")
    day.create_completion!

    assert_difference -> { PlanCompletion.count }, -1 do
      delete uncomplete_reading_plan_plan_day_path(plan, day)
    end
    assert_response :success
  end

  test "guests cannot reach reading plans" do
    delete session_path # log out
    get reading_plans_path
    assert_redirected_to new_session_path
  end
end
