require "test_helper"

class AiRequestTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    @study = @user.studies.create!(name: "S", pane_count: 1)
  end

  test "start! makes an unguessable token and enqueues the job" do
    req = nil
    assert_enqueued_with(job: AiRequestJob) do
      req = AiRequest.start!(user: @user, study: @study, kind: "quick_find", params: { q: "grace" })
    end
    assert req.pending?
    assert_operator req.token.length, :>=, 32
    assert_equal req.token, req.to_param
  end

  test "an identical pending request is reused; a different one is not" do
    a = AiRequest.start!(user: @user, study: @study, kind: "quick_find", params: { q: "grace" })
    assert_equal a, AiRequest.start!(user: @user, study: @study, kind: "quick_find", params: { q: "grace" })
    refute_equal a, AiRequest.start!(user: @user, study: @study, kind: "quick_find", params: { q: "mercy" })
    a.update!(status: "done")
    refute_equal a, AiRequest.start!(user: @user, study: @study, kind: "quick_find", params: { q: "grace" })
  end

  test "prune! drops day-old rows" do
    old = AiRequest.create!(user: @user, study: @study, kind: "rabbi", params: {})
    old.update_columns(created_at: 2.days.ago)
    fresh = AiRequest.create!(user: @user, study: @study, kind: "rabbi", params: {})
    AiRequest.prune!
    assert_not AiRequest.exists?(old.id)
    assert AiRequest.exists?(fresh.id)
  end

  test "fail! hands an illustration slot back once" do
    quota = IllustrationQuota.for(IllustrationQuota.key_for(@user))
    assert quota.reserve!
    req = AiRequest.create!(user: @user, study: @study, kind: "rabbi_illustration", params: {}, illustration_quota_id: quota.id)
    req.fail!(:timeout)
    req.fail!(:timeout)
    assert_equal 0, quota.reload.count
    assert_equal "timeout", req.reload.error
  end

  test "stale? only for pending rows past STALE_AFTER" do
    req = AiRequest.create!(user: @user, study: @study, kind: "rabbi", params: {})
    assert_not req.stale?
    req.update_columns(created_at: 1.hour.ago)
    assert req.stale?
    req.update!(status: "done")
    assert_not req.stale?
  end

  test "a late answer never overwrites a request that already timed out" do
    req = AiRequest.create!(user: @user, study: @study, kind: "quick_find", params: { q: "grace" })
    original = AiWork.method(:run)
    AiWork.define_singleton_method(:run) do |r|
      AiRequest.find(r.id).fail!(:timeout) # the page gave up while the model was thinking
      { "ok" => true }
    end
    req.perform!
    assert req.reload.failed?
    assert_equal "timeout", req.error
  ensure
    AiWork.define_singleton_method(:run, original)
  end
end
