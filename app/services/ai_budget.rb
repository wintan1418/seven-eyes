# Spend guards for every paid AI call, kept in the shared cache (Solid Cache in
# production, so all Puma workers see the same counters).
#
#   * A GLOBAL daily cap across all users — the backstop against a runaway bill
#     no matter which code path (Rabbi, prayer, quick find, images) is calling.
#       AI_DAILY_CHAT_LIMIT  (default 3000 chat completions / day)
#       AI_DAILY_IMAGE_LIMIT (default 100 image generations / day)
#       AI_DAILY_SPEECH_LIMIT (default 1000 TTS chunks / day)
#   * A PER-USER daily cap on the interactive AI endpoints.
#       AI_USER_DAILY_LIMIT  (default 150 AI requests / user / day)
#
# Counters are bucketed by UTC date and expire after two days. Exceeding a cap
# never raises — callers get `false` and degrade to a friendly message.
class AiBudget
  DEFAULT_LIMITS = { chat: 3000, image: 100, speech: 1000 }.freeze
  DEFAULT_USER_LIMIT = 150
  TTL = 2.days

  class << self
    # Reserve one unit of global spend of the given kind (:chat / :image).
    # Returns true when allowed (and counts it), false when today's cap is spent.
    def charge(kind = :chat)
      take("ai_budget/global/#{kind}/#{today}", global_limit(kind))
    end

    # Reserve one interactive AI request for this user today.
    def charge_user(user_id)
      take("ai_budget/user/#{user_id}/#{today}", user_limit)
    end

    def global_limit(kind)
      env = ENV["AI_DAILY_#{kind.to_s.upcase}_LIMIT"].presence
      (env || DEFAULT_LIMITS.fetch(kind.to_sym, DEFAULT_LIMITS[:chat])).to_i
    end

    def user_limit = (ENV["AI_USER_DAILY_LIMIT"].presence || DEFAULT_USER_LIMIT).to_i

    def used(kind = :chat) = Rails.cache.read("ai_budget/global/#{kind}/#{today}", raw: true).to_i

    private

    def today = Time.now.utc.to_date.iso8601

    # Increment first, then compare: two concurrent callers can never both take
    # the last slot. A cache that can't count (e.g. :null_store) yields nil — we
    # fail OPEN there rather than switching AI off in dev/test.
    def take(key, limit)
      return false if limit <= 0
      count = Rails.cache.increment(key, 1, expires_in: TTL)
      return true if count.nil?
      count <= limit
    rescue => e
      Rails.logger.warn("[AiBudget] #{e.class}: #{e.message}")
      true
    end
  end
end
