require "test_helper"

class StudyTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "a new study builds pane_count empty panes in order" do
    study = @user.studies.create!(name: "Test", pane_count: 3)
    assert_equal 3, study.panes.count
    assert_equal [ 0, 1, 2 ], study.panes.map(&:position)
    assert study.panes.all?(&:empty?)
  end

  test "pane_count must be between 1 and 4" do
    refute @user.studies.build(name: "x", pane_count: 0).valid?
    refute @user.studies.build(name: "x", pane_count: 5).valid?
    assert @user.studies.build(name: "x", pane_count: 4).valid?
  end

  test "sync_panes! grows and shrinks panes to match pane_count" do
    study = @user.studies.create!(name: "Test", pane_count: 2)
    study.update!(pane_count: 4)
    study.sync_panes!
    assert_equal [ 0, 1, 2, 3 ], study.reload.panes.map(&:position)

    study.update!(pane_count: 1)
    study.sync_panes!
    assert_equal [ 0 ], study.reload.panes.map(&:position)
  end
end
