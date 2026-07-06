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
end
