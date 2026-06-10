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
end
