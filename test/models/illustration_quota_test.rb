require "test_helper"

class IllustrationQuotaTest < ActiveSupport::TestCase
  test "starts empty and allows up to the daily limit" do
    q = IllustrationQuota.for("u1")
    assert_equal 0, q.count
    assert_equal IllustrationQuota.limit, q.remaining
    assert_not q.exceeded?
  end

  test "record! bumps the count and reduces remaining" do
    q = IllustrationQuota.for("u1")
    q.record!
    assert_equal 1, q.reload.count
    assert_equal IllustrationQuota.limit - 1, q.remaining
  end

  test "exceeded? flips once the limit is reached" do
    q = IllustrationQuota.for("u1")
    IllustrationQuota.limit.times { q.record! }
    assert q.reload.exceeded?
    assert_equal 0, q.remaining
  end

  test "the same owner shares one row per day" do
    IllustrationQuota.for("u7").record!
    IllustrationQuota.for("u7").record!
    assert_equal 1, IllustrationQuota.where(owner_key: "u7", day: Date.current).count
    assert_equal 2, IllustrationQuota.for("u7").count
  end

  test "a new day gets a fresh allowance" do
    IllustrationQuota.for("u9", day: Date.current - 1).tap { |q| IllustrationQuota.limit.times { q.record! } }
    today = IllustrationQuota.for("u9")
    assert_equal 0, today.count
    assert_not today.exceeded?
  end

  test "distinct owners are independent" do
    IllustrationQuota.for("u1").record!
    assert_equal 0, IllustrationQuota.for("g2").count
  end

  test "reserve! takes slots up to the limit and then refuses" do
    q = IllustrationQuota.for("u3")
    IllustrationQuota.limit.times { assert q.reserve! }
    assert_not q.reserve!, "no slot beyond the daily cap"
    assert_equal IllustrationQuota.limit, q.reload.count
  end

  test "reserve! is a conditional UPDATE, so a stale copy can't overshoot the cap" do
    a = IllustrationQuota.for("u4")
    b = IllustrationQuota.find(a.id) # a second request holding its own stale copy
    (IllustrationQuota.limit - 1).times { a.reserve! }

    assert b.reserve!, "the last slot can be taken once"
    assert_not a.reserve!, "...and only once, whoever's copy asks"
    assert_equal IllustrationQuota.limit, IllustrationQuota.find(a.id).count
  end

  test "release! hands a slot back but never goes below zero" do
    q = IllustrationQuota.for("u5")
    q.reserve!
    q.release!
    assert_equal 0, q.count
    q.release!
    assert_equal 0, q.reload.count
  end

  test "for tolerates the row already existing (create_or_find_by)" do
    first = IllustrationQuota.for("u6")
    assert_no_difference -> { IllustrationQuota.count } do
      assert_equal first.id, IllustrationQuota.for("u6").id
    end
  end

  test "key_for keys quotas by user id" do
    assert_equal "u42", IllustrationQuota.key_for(42)
  end
end
