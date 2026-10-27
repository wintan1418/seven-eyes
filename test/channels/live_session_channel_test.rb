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

  test "follower counts go only to the operator stream, never to followers" do
    operator_stream = LiveSessionChannel.operator_broadcasting_for(@live)
    assert_broadcasts(operator_stream, 1) do
      assert_no_broadcasts(LiveSessionChannel.broadcasting_for(@live)) do
        subscribe code: @live.code
      end
    end
    assert_equal({ "type" => "count", "followers" => 1 }, JSON.parse(broadcasts(operator_stream).last))
  end

  test "the operator subscribes with its signed token and is not counted" do
    subscribe code: @live.code, role: "operator", token: @live.operator_token
    assert subscription.confirmed?
    assert_has_stream LiveSessionChannel.operator_broadcasting_for(@live)
    assert_no_streams_for_followers
    assert_equal({ "type" => "count", "followers" => 0 }, transmissions.last)
    assert_equal 0, @live.reload.followers_count
  end

  test "an operator subscription without a valid token is rejected" do
    subscribe code: @live.code, role: "operator"
    assert subscription.rejected?

    subscribe code: @live.code, role: "operator", token: "forged"
    assert subscription.rejected?

    other = @study.live_sessions.create!
    subscribe code: @live.code, role: "operator", token: other.operator_token
    assert subscription.rejected?, "a token for another session must not unlock this one"
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

  test "a stale session is expired on subscribe and the follower is rejected" do
    @live.update_column(:updated_at, (LiveSession::STALE_AFTER + 1.minute).ago)
    subscribe code: @live.code
    assert subscription.rejected?
    assert @live.reload.ended?
  end

  test "resync transmits the current state to the (re)connecting follower" do
    Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    subscribe code: @live.code
    @live.update!(kind: "scripture", osis: "John", chapter: 3, verse_start: 16, verse_end: 16,
                  translation_code: "KJV")
    perform :resync
    state = transmissions.last
    assert_equal "state", state["type"]
    assert_equal "John", state["osis"]
    assert_equal 3, state["chapter"]
    assert_equal 16, state["verse_start"]
    assert_equal "John 3", state["reference"]
  end

  private

  def assert_no_streams_for_followers
    refute_includes subscription.streams, LiveSessionChannel.broadcasting_for(@live)
  end
end
