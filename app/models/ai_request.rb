# An AI question running in the background (Quick Find, the Rabbi, an
# illustration). The web request creates the row, enqueues AiRequestJob and
# answers at once with a "thinking" state, so no Puma thread ever waits on a
# model; the page polls GET /studies/:id/ai_requests/:token until the job has
# written the answer (`result`, the serialized service result — see AiWork).
#
# Only the asker can read it: polling is scoped to the signed-in user AND the
# study they can open (current_study), and the token is unguessable.
class AiRequest < ApplicationRecord
  KINDS = %w[ quick_find rabbi rabbi_illustration ].freeze
  # The worker normally answers in 5–40 s. Past this a pending row is reported
  # as timed out (worker down / job lost), so the page offers Retry instead of
  # spinning forever.
  STALE_AFTER = 3.minutes
  KEEP_FOR = 1.day

  belongs_to :user
  belongs_to :study

  enum :status, { pending: "pending", done: "done", failed: "failed" }, validate: true

  validates :kind, inclusion: { in: KINDS }
  validates :token, presence: true, uniqueness: true

  before_validation { self.token ||= SecureRandom.urlsafe_base64(24) }

  # Create (or reuse an identical one already thinking — a double-click or a
  # re-ask must not pay twice) and enqueue. Requests holding an illustration
  # slot are never shared: each one reserved its own slot.
  def self.start!(user:, study:, kind:, params:, quota: nil)
    prune!
    fingerprint = Digest::SHA256.hexdigest([ kind, study.id, params.to_a.sort ].to_json)
    unless quota
      existing = where(user:, study:, fingerprint:, status: "pending")
                   .where(created_at: STALE_AFTER.ago..).order(:created_at).last
      return existing if existing
    end

    create!(user:, study:, kind:, params:, fingerprint:, illustration_quota_id: quota&.id).tap do |req|
      AiRequestJob.perform_later(req.id)
    end
  end

  def self.prune!
    where(created_at: ...KEEP_FOR.ago).delete_all
  end

  def stale? = pending? && created_at < STALE_AFTER.ago

  # Called by the job: run the work and store the answer. Never raises — a
  # crash is recorded as a failure (and an illustration slot handed back).
  def perform!
    return unless pending?

    result = AiWork.run(self)
    # Only if nobody gave up on it meanwhile (a poll past STALE_AFTER marks it
    # timed out and has already handed any illustration slot back).
    written = self.class.where(id:, status: "pending")
                  .update_all(result:, status: "done", finished_at: Time.current, updated_at: Time.current)
    reload if written == 1
  rescue => e
    Rails.logger.error("[AiRequest #{id}] #{kind}: #{e.class}: #{e.message}")
    fail!(:api)
  end

  # Conditional on the row still pending, so a timeout and a crash (or two
  # polls) can't both hand the same illustration slot back.
  def fail!(code)
    written = self.class.where(id:, status: "pending")
                  .update_all(status: "failed", error: code.to_s, finished_at: Time.current, updated_at: Time.current)
    reload
    release_quota! if written == 1
  end

  # Give an illustration slot back when no picture came of it.
  def release_quota!
    IllustrationQuota.find_by(id: illustration_quota_id)&.release! if illustration_quota_id
  end

  def to_param = token
end
