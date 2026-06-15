require "test_helper"

class LiveSessionChannelTest < ActionCable::Channel::TestCase
  setup do
    @study = users(:one).studies.create!(name: "Sunday", pane_count: 1)
    @live = @study.live_sessions.create!
  end

  test "a follower subscribes, streams, and is counted" do
    subscribe code: @live.code
    assert subscription.confirmed?
    assert_has_stream_for @live
    assert_equal 1, @live.reload.followers_count
  end

  test "the operator subscription is not counted as a follower" do
    subscribe code: @live.code, role: "operator"
    assert subscription.confirmed?
    assert_equal 0, @live.reload.followers_count
  end

  test "unsubscribing a follower decrements the count" do
    subscribe code: @live.code
    unsubscribe
    assert_equal 0, @live.reload.followers_count
  end

  test "rejects an unknown or ended code" do
    @live.end!
    subscribe code: @live.code
    assert subscription.rejected?
  end

  test "resync transmits the current state to the (re)connecting follower" do
    Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    @live.update!(kind: "scripture", osis: "John", chapter: 3, verse_start: 16, verse_end: 16,
                  translation_code: "KJV")
    subscribe code: @live.code
    perform :resync
    state = transmissions.last
    assert_equal "state", state["type"]
    assert_equal "John", state["osis"]
    assert_equal 3, state["chapter"]
    assert_equal 16, state["verse_start"]
    assert_equal "John 3", state["reference"]
  end
end
