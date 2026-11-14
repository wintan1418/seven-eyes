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
end
