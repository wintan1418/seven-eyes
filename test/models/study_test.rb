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

  test "sync_panes! grows and hides panes to match pane_count" do
    study = @user.studies.create!(name: "Test", pane_count: 2)
    study.update!(pane_count: 4)
    study.sync_panes!
    assert_equal [ 0, 1, 2, 3 ], study.reload.panes.map(&:position)

    study.update!(pane_count: 1)
    study.sync_panes!
    assert_equal [ 0 ], study.reload.panes.map(&:position)
    assert_equal 4, study.all_panes.count, "lowering the count hides panes, never destroys them"
  end

  test "lowering then raising the pane count keeps notes in the hidden panes" do
    study = @user.studies.create!(name: "Test", pane_count: 4)
    third = study.panes.find_by(position: 2)
    third.update!(reference: "Rom 5", notes: "Peace with God — preach this first")

    study.update!(pane_count: 2)
    study.sync_panes!
    assert_equal [ 0, 1 ], study.reload.panes.map(&:position)
    assert_nil study.panes.find_by(id: third.id), "hidden panes are not addressable"

    study.update!(pane_count: 4)
    study.sync_panes!
    restored = study.reload.panes.find_by(position: 2)
    assert_equal third.id, restored.id
    assert_equal "Peace with God — preach this first", restored.notes
    assert_equal 4, study.all_panes.count
  end

  test "destroying a study removes hidden panes too" do
    study = @user.studies.create!(name: "Test", pane_count: 3)
    study.update!(pane_count: 1)
    study.sync_panes!
    assert_difference -> { Pane.count }, -3 do
      study.destroy
    end
  end

  test "panes preload for many studies at once" do
    a = @user.studies.create!(name: "A", pane_count: 1)
    @user.studies.create!(name: "B", pane_count: 3)
    loaded = @user.studies.where(id: [ a.id ]).includes(:panes).to_a
    assert_equal [ 0 ], loaded.first.panes.map(&:position)
  end
end
