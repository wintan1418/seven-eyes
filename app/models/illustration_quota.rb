# A per-user, per-day counter for AI image generations, so illustrating a passage
# can't run up an unbounded OpenAI bill. One row per (owner_key, day); owner_key
# is "u<user_id>" (illustrations require an account — guests never reach the
# image model). The daily cap is ILLUSTRATION_DAILY_LIMIT (default 4). A new day
# means a new row, so the count resets naturally at midnight (server time).
#
# Slots are RESERVED before the paid API call with a single conditional UPDATE
# (count < limit), so concurrent requests can't overshoot the cap; a failed
# generation hands its slot back with #release!.
class IllustrationQuota < ApplicationRecord
  # "quota".pluralize == "quota", so Rails would infer the singular table name;
  # the migration creates the conventional plural table, so pin it.
  self.table_name = "illustration_quotas"

  DEFAULT_LIMIT = 4

  def self.limit
    (ENV["ILLUSTRATION_DAILY_LIMIT"].presence || DEFAULT_LIMIT).to_i
  end

  def self.key_for(user) = "u#{user.is_a?(User) ? user.id : user}"

  # Today's quota row for this owner, created on first use. create_or_find_by!
  # leans on the unique (owner_key, day) index, so two first requests racing
  # each other both end up with the same row instead of one raising.
  def self.for(owner_key, day: Date.current)
    create_or_find_by!(owner_key: owner_key.to_s, day: day)
  end

  def remaining = [ self.class.limit - count, 0 ].max
  def exceeded? = count >= self.class.limit

  # Atomically take one slot. Returns true if a slot was reserved (and reloads
  # the count), false when today's allowance is already spent.
  def reserve!
    taken = self.class.where(id: id).where("count < ?", self.class.limit)
                .update_all([ "count = count + 1, updated_at = ?", Time.current ]) == 1
    reload
    taken
  end

  # Give back a reserved slot (the generation failed, so it shouldn't count).
  def release!
    self.class.where(id: id).where("count > 0")
        .update_all([ "count = count - 1, updated_at = ?", Time.current ])
    reload
  end

  # Unconditionally bump the counter (kept for callers/tests that record after
  # the fact); prefer reserve! before a paid call.
  def record! = increment!(:count)
end
