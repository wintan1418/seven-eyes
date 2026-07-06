# A per-user, per-day counter for AI image generations, so illustrating a passage
# can't run up an unbounded OpenAI bill. One row per (owner_key, day); owner_key is
# "u<user_id>" for members or "g<study_id>" for guests. The daily cap is
# ILLUSTRATION_DAILY_LIMIT (default 4). A new day means a new row, so the count
# resets naturally at midnight (server time) — no sweeping needed.
class IllustrationQuota < ApplicationRecord
  # "quota".pluralize == "quota", so Rails would infer the singular table name;
  # the migration creates the conventional plural table, so pin it.
  self.table_name = "illustration_quotas"

  DEFAULT_LIMIT = 4

  def self.limit
    (ENV["ILLUSTRATION_DAILY_LIMIT"].presence || DEFAULT_LIMIT).to_i
  end

  # Today's quota row for this owner, created on first use.
  def self.for(owner_key, day: Date.current)
    find_or_create_by!(owner_key: owner_key.to_s, day: day)
  end

  def remaining = [ self.class.limit - count, 0 ].max
  def exceeded? = count >= self.class.limit

  # Atomically bump the counter for a successful generation.
  def record! = increment!(:count)
end
