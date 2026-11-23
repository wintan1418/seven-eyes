require "test_helper"

# Study::Serving — a queue as a service that happened on a day.
class StudyServingTest < ActiveSupport::TestCase
  setup do
    Book.create!(osis_code: "Ps", name: "Psalms", testament: :old, position: 19, chapter_count: 150)
    @user = users(:one)
    @study = @user.studies.create!(name: "Psalms 4", pane_count: 1)
    @study.panes.first.update!(reference: "Psalm 4")
    @study.setlist_items.create!(kind: :scripture, reference: "Psalm 4:1", client_id: "tmp-a")
    @study.setlist_items.create!(kind: :song, title: "Abide with Me", body: "Abide with me")
    @study.setlist_items.create!(kind: :thought, body: "Welcome")
  end

  # Sunday 22 Nov 2026, 10:00 in Lagos (UTC+1).
  def sunday_morning = Time.utc(2026, 11, 22, 9, 0)

  test "the first time it goes live on a day is recorded once; later pings that day change nothing" do
    travel_to sunday_morning do
      assert @study.mark_served!(Time.current)
      first = @study.reload.last_served_at
      travel 2.hours
      assert_not @study.mark_served!(Time.current)
      assert_equal first, @study.reload.last_served_at
      assert_equal Date.new(2026, 11, 22), @study.served_on
    end
  end

  test "the day is the app's calendar day (Lagos): 23:30 UTC on Saturday is Sunday's service" do
    travel_to Time.utc(2026, 11, 21, 23, 30) do
      @study.mark_served!(Time.current)
      assert_equal Date.new(2026, 11, 22), @study.reload.served_on
    end
  end

  test "a new day moves it on; an old replay never moves it back; nonsense times count as now" do
    travel_to sunday_morning do
      @study.mark_served!(3.days.ago)
      assert_equal Date.new(2026, 11, 19), @study.reload.served_on
      assert @study.mark_served!(Time.current)
      assert_equal Date.new(2026, 11, 22), @study.reload.served_on
      assert_not @study.mark_served!(2.days.ago)
      assert_equal Date.new(2026, 11, 22), @study.reload.served_on

      other = @user.studies.create!(name: "Other", pane_count: 1)
      other.mark_served!(1.year.from_now)
      assert_in_delta Time.current, other.reload.last_served_at, 1.second
    end
  end

  test "Quick Present and archived copies are never services" do
    qp = @user.studies.create!(name: "Quick Present", pane_count: 1, quick_present: true)
    assert_not qp.mark_served!
    assert_nil qp.reload.last_served_at
  end

  test "served before today: from the next calendar day on, until kept" do
    travel_to sunday_morning do
      @study.mark_served!
      assert_not @study.served_before?(Date.new(2026, 11, 22))
      assert @study.served_before?(Date.new(2026, 11, 23))
      @study.keep_for_next_service!
      assert @study.kept_for_next_service?
      assert_not @study.served_before?(Date.new(2026, 11, 23))
    end
    # Served again a week later: kept no longer applies.
    travel_to sunday_morning + 7.days do
      @study.mark_served!
      assert_not @study.kept_for_next_service?
      assert @study.served_before?(Date.new(2026, 11, 30))
    end
  end

  test "start fresh moves the queue into an archived copy named for the service day, and empties this one" do
    travel_to sunday_morning do
      @study.mark_served!
      served_at = @study.reload.last_served_at
      archive = @study.start_fresh!(key: "tmp-fresh-1")

      assert_equal "Service · 22 Nov 2026", archive.name
      assert archive.archived?
      assert_equal @study, archive.archived_from
      assert_equal served_at.to_i, archive.last_served_at.to_i
      assert_equal "Psalm 4", archive.panes.first.reference
      assert_equal [ "Psalm 4:1", "Abide with Me", "Welcome" ], archive.setlist_items.in_order.map { |i| i.reference || i.title || i.body }
      assert_equal 0, @study.setlist_items.count
      assert_nil @study.reload.last_served_at
      assert_equal Date.new(2026, 11, 22), @study.planned_for, "emptied for the coming Sunday (today, on a Sunday)"

      # A replay of the same request moves nothing else and makes no second copy.
      @study.setlist_items.create!(kind: :scripture, reference: "Psalm 23")
      assert_equal archive, @study.start_fresh!(key: "tmp-fresh-1")
      assert_equal 1, @study.setlist_items.count
      assert_equal 1, Study.archived.count
    end
  end

  test "undo puts the old items back on top, keeps what was added since, restores the service day, drops the copy" do
    travel_to sunday_morning do
      @study.mark_served!
      @study.start_fresh!(key: "tmp-fresh-2")
      @study.setlist_items.create!(kind: :scripture, reference: "Psalm 23")

      assert @study.undo_start_fresh!("tmp-fresh-2")
      labels = @study.setlist_items.in_order.map { |i| i.reference || i.title || i.body }
      assert_equal [ "Psalm 4:1", "Abide with Me", "Welcome", "Psalm 23" ], labels
      assert_equal Date.new(2026, 11, 22), @study.reload.served_on
      assert_equal 0, Study.archived.count
      assert_not @study.undo_start_fresh!("tmp-fresh-2"), "a second undo is a no-op"
      assert_not @study.undo_start_fresh!("never-made"), "an unknown key is a no-op"
    end
  end

  test "start fresh on an empty queue makes no copy" do
    @study.setlist_items.destroy_all
    assert_nil @study.start_fresh!(key: "tmp-empty")
    assert_equal 0, Study.archived.count
  end

  test "copy_service! makes a new service for the coming Sunday with the same order" do
    copy = @study.copy_service!(planned_for: Date.new(2026, 11, 29))
    assert_equal "Service · 29 Nov 2026", copy.name
    assert_equal Date.new(2026, 11, 29), copy.planned_for
    assert_equal "Psalm 4", copy.panes.first.reference
    assert_equal @study.setlist_items.in_order.map(&:kind), copy.setlist_items.in_order.map(&:kind)
    assert_equal [ nil, nil, nil ], copy.setlist_items.map(&:client_id)
    assert_equal 3, @study.setlist_items.count, "the original keeps its queue"
  end

  test "the coming Sunday and the app's calendar" do
    assert_equal Date.new(2026, 11, 22), Study.next_sunday(Date.new(2026, 11, 22))
    assert_equal Date.new(2026, 11, 29), Study.next_sunday(Date.new(2026, 11, 23))
    assert_equal Date.new(2026, 11, 22), Study.service_date(Time.utc(2026, 11, 21, 23, 30))
  end

  test "scopes: served (newest first, no Quick Present), archived / unarchived, shelf" do
    travel_to sunday_morning do
      older = @user.studies.create!(name: "Older", pane_count: 1, last_served_at: 7.days.ago)
      @study.mark_served!
      assert_equal [ @study, older ], @user.studies.served.to_a
      archive = @study.start_fresh!(key: "tmp-scope")
      assert_includes @user.studies.served, archive
      assert_includes Study.archived, archive
      assert_not_includes @user.studies.shelf, archive
      assert_includes @user.studies.shelf, @study
    end
  end
end
