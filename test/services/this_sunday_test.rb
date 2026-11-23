require "test_helper"

class ThisSundayTest < ActiveSupport::TestCase
  setup do
    { "John" => 43, "Jer" => 24 }.each do |osis, pos|
      Book.create!(osis_code: osis, name: osis == "Jer" ? "Jeremiah" : "John", testament: pos > 39 ? :new : :old, position: pos, chapter_count: 52)
    end
    @user = users(:one)
    @old = @user.studies.create!(name: "Last week", pane_count: 1, last_opened_at: 3.days.ago)
    @old.setlist_items.create!(kind: :scripture, reference: "John 1:1")
    @service = @user.studies.create!(name: "The Potter's House", pane_count: 1, last_opened_at: 1.hour.ago)
    @service.setlist_items.create!(kind: :thought, body: "Welcome, church family.\n\nLet us worship.")
    @service.setlist_items.create!(kind: :song, title: "Be Thou My Vision", body: "Be thou my vision")
    @service.setlist_items.create!(kind: :song, title: "Holy, Holy, Holy", body: "Holy holy holy", arrangement: "V1 V2")
    @service.setlist_items.create!(kind: :scripture, reference: "Jeremiah 18:1-6")
    @user.studies.create!(name: "No queue, opened just now", pane_count: 1, last_opened_at: Time.current)
  end

  test "the most recently opened study with a queue is this Sunday's service" do
    sunday = ThisSunday.for(@user)
    assert_equal @service, sunday.study
    assert_equal [ "Note", "Song", "Song", "Scripture" ], sunday.shown.map { |i| ThisSunday.kind_label(i) }
    assert_equal "Welcome, church family.", ThisSunday.item_title(sunday.shown.first)
    assert_equal({ scripture: 1, song: 2, slides: 1 }, sunday.counts)
  end

  test "readiness: songs with no order, a missing scripture" do
    checks = ThisSunday.for(@user).checks
    assert_equal [ [ :todo, "1 song has no order yet" ] ], checks.map { |c| [ c.state, c.text ] }

    @service.setlist_items.scripture.destroy_all
    @service.setlist_items.song.update_all(arrangement: "V1")
    texts = ThisSunday.for(@user).checks.map(&:text)
    assert_equal [ "Every song has its order", "No scripture in the order yet" ], texts
  end

  test "the coming Sunday" do
    sunday = ThisSunday.for(@user)
    assert_equal Date.new(2026, 11, 15), sunday.date(Date.new(2026, 11, 14))
    assert_equal Date.new(2026, 11, 15), sunday.date(Date.new(2026, 11, 15))
    assert_equal Date.new(2026, 11, 22), sunday.date(Date.new(2026, 11, 16))
  end

  test "no queue anywhere: no This Sunday; Quick Present doesn't count" do
    assert_nil ThisSunday.for(users(:two))
    qp = users(:two).studies.create!(name: "Quick Present", pane_count: 1, quick_present: true)
    qp.setlist_items.create!(kind: :scripture, reference: "John 1:1")
    assert_nil ThisSunday.for(users(:two))
  end

  # ---- after the service (Study::Serving) ----------------------------------------

  def monday = Date.new(2026, 11, 23)

  test "on the day of the service it is still Today's service" do
    travel_to Time.utc(2026, 11, 22, 9) do
      @service.mark_served!
      sunday = ThisSunday.for(@user)
      assert_equal @service, sunday.study
      assert_not sunday.past?
      assert_equal sunday.today, sunday.date
    end
  end

  test "once the day it was served has passed, it is last Sunday's, not this Sunday's" do
    travel_to Time.utc(2026, 11, 22, 9) do
      @service.mark_served!
    end
    travel_to Time.utc(2026, 11, 22, 22, 59) do # 23:59 in Lagos: still Sunday
      assert_not ThisSunday.for(@user).past?
    end
    travel_to Time.utc(2026, 11, 22, 23, 1) do # 00:01 Monday in Lagos
      sunday = ThisSunday.for(@user)
      assert sunday.past?
      assert_equal @service, sunday.study
      assert_equal "Last Sunday, 22 Nov", sunday.served_label
      assert_equal Date.new(2026, 11, 29), sunday.date
      assert_equal 4, sunday.items.size
    end
  end

  test "an older queue nobody opened since the service is not this Sunday's either" do
    @service.update_columns(last_served_at: Time.utc(2026, 11, 22, 9))
    @old.update_columns(last_opened_at: Time.utc(2026, 11, 19, 9)) # before the service
    sunday = ThisSunday.for(@user, today: monday)
    assert sunday.past?
    assert_equal @service, sunday.study
  end

  test "a queue opened (or planned) since the last service is this Sunday's" do
    @service.update_columns(last_served_at: Time.utc(2026, 11, 22, 9))
    @old.update_columns(last_opened_at: Time.utc(2026, 11, 23, 8))
    assert_equal @old, ThisSunday.for(@user, today: monday).study
    assert_not ThisSunday.for(@user, today: monday).past?

    @old.update_columns(last_opened_at: Time.utc(2026, 11, 19, 9))
    planned = @user.studies.create!(name: "Service · 29 Nov 2026", pane_count: 1, planned_for: Date.new(2026, 11, 29),
                                    last_opened_at: Time.utc(2026, 11, 20))
    sunday = ThisSunday.for(@user, today: monday)
    assert_equal planned, sunday.study, "a planned service counts even before anything is queued"
    assert_not sunday.past?
  end

  test "Keep using it makes a served queue this Sunday's again" do
    @service.update_columns(last_served_at: Time.utc(2026, 11, 22, 9))
    @service.keep_for_next_service!
    sunday = ThisSunday.for(@user, today: monday)
    assert_equal @service, sunday.study
    assert_not sunday.past?
  end

  test "archived copies (Start fresh) are never this Sunday" do
    travel_to Time.utc(2026, 11, 22, 9) { @service.mark_served! }
    travel_to Time.utc(2026, 11, 23, 9) do
      archive = @service.start_fresh!(key: "tmp-archive-test")
      sunday = ThisSunday.for(@user)
      assert_not_equal archive, sunday.study
      assert_equal @service, sunday.study, "the emptied queue is planned for the coming Sunday"
      assert_not sunday.past?
    end
  end

  test "a midweek service reads as the last service, with its weekday" do
    @service.update_columns(last_served_at: Time.utc(2026, 11, 18, 18))
    @old.update_columns(last_opened_at: Time.utc(2026, 11, 10))
    sunday = ThisSunday.for(@user, today: Date.new(2026, 11, 19))
    assert sunday.past?
    assert_equal "Last service, Wed 18 Nov", sunday.served_label
  end
end
