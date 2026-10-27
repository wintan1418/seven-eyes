# A live "follow along" broadcast for a study's preach mode. The pastor goes
# live and gets a short join code; congregants open /live/CODE on their phones
# and the current passage follows the pulpit in real time over Action Cable.
#
# State columns mirror what the operator last projected: book (OSIS) + chapter,
# the emphasised verse range, and the translation code. `followers_count` is
# adjusted by LiveSessionChannel as phones subscribe/unsubscribe.
#
# Lifetime: a session ends when the operator presses "End live", or lazily once
# nothing has been pushed for STALE_AFTER (a console closed mid-service never
# leaves a session "live" forever). The recap of an ended service stays public
# for RECAP_TTL, then the farewell page stops listing it.
class LiveSession < ApplicationRecord
  belongs_to :study

  # No 0/O, 1/I/L — the code gets read aloud and typed from the back pew.
  CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789".chars.freeze
  # Six characters from a 31-letter alphabet ≈ 887M codes — not guessable by
  # walking the space. Older 4-character codes still resolve (lookup is by
  # exact code, whatever its length).
  CODE_LENGTH = 6
  FALLBACK_CODE_LENGTH = 10

  STALE_AFTER = 6.hours
  RECAP_TTL = 7.days
  PASSAGE_LOG_LIMIT = 100

  before_validation :assign_code, on: :create
  validates :code, presence: true, uniqueness: true

  scope :active, -> { where(ended_at: nil) }

  # The active session for a join code, or nil. A session that has gone quiet
  # for STALE_AFTER is ended on the spot (lazy expiry — no cron needed).
  def self.find_active(code)
    live = active.find_by(code: normalize_code(code))
    expire_if_stale(live)
  end

  # The study's current session (newest active one), expiring it if stale.
  def self.current_for(study)
    live = study.live_sessions.active.order(created_at: :desc).first
    expire_if_stale(live)
  end

  # Go live idempotently: concurrent "Go Live" clicks (double-click, two tabs)
  # serialise on the study row, so only one session is ever created.
  def self.start_for!(study)
    study.with_lock { current_for(study) || study.live_sessions.create! }
  end

  def self.normalize_code(code)
    code.to_s.strip.upcase
  end

  def self.expire_if_stale(live)
    return nil unless live
    return live unless live.stale?
    live.expire!
    nil
  end

  def self.random_code(length)
    Array.new(length) { CODE_ALPHABET[SecureRandom.random_number(CODE_ALPHABET.size)] }.join
  end

  def self.find_by_operator_token(token)
    find_signed(token.to_s, purpose: :live_operator)
  end

  def ended? = ended_at.present?

  def stale?
    !ended? && updated_at.present? && updated_at < STALE_AFTER.ago
  end

  # Ended sessions keep their "tonight's scriptures" list for a week.
  def recap_available?
    !ended? || ended_at > RECAP_TTL.ago
  end

  # Proves the bearer is the console that started this session — the operator
  # cable subscription (follower count) requires it.
  def operator_token
    signed_id(purpose: :live_operator, expires_in: 1.day)
  end

  # A non-scripture moment: a song stanza or a projected thought/announcement.
  def slide? = kind == "slide"

  def slide_stanzas
    slide_body.to_s.split(/\n{2,}/).map(&:strip).reject(&:empty?)
  end

  # Recap trail: every passage the congregation was shown, in order. Consecutive
  # pushes within the same chapter collapse into one entry.
  def log_passage!
    return if osis.blank? || chapter.blank?
    entry = { "osis" => osis, "chapter" => chapter, "label" => reference_label }
    return if passages.last == entry
    update_column(:passages, (passages + [ entry ]).last(PASSAGE_LOG_LIMIT))
  end

  def end!
    update!(ended_at: Time.current, followers_count: 0) unless ended?
  end

  # Lazy expiry: end the session and tell anyone still subscribed.
  def expire!
    end!
    LiveSessionChannel.broadcast_to(self, { type: "ended" })
  end

  def book
    @book ||= Book.find_by_osis(osis) if osis.present?
  end

  def translation
    @translation ||= Translation.find_by(code: translation_code) ||
                     Translation.find_by(code: Pane::DEFAULT_TRANSLATION)
  end

  def verses
    return Verse.none unless book && chapter && translation
    Verse.where(translation: translation, book: book, chapter: chapter).order(:verse_number)
  end

  def reference_label
    return nil unless book && chapter
    "#{Bible::Canon.find(book.osis_code)&.name || book.name} #{chapter}"
  end

  # The cable payload for the current state. Used both when broadcasting a change
  # to every follower AND when a single (re)connecting follower asks to resync —
  # e.g. after the phone's Wi-Fi dropped and Action Cable silently reconnected.
  def live_state
    if slide?
      { type: "state", kind: "slide",
        slide_title: slide_title, slide_body: slide_body,
        slide_image_url: slide_image_url, slide_index: slide_index.to_i,
        reference: slide_title.presence || "—" }
    else
      { type: "state", kind: "scripture",
        osis: osis, chapter: chapter,
        verse_start: verse_start, verse_end: verse_end,
        emphasis: emphasis || {},
        translation: translation_code, reference: reference_label }
    end
  end

  # One atomic UPDATE … RETURNING (clamped at zero) — a follower joining costs a
  # single query, not update + reload + fix-up.
  def adjust_followers(delta)
    sql = self.class.sanitize_sql_array([
      "UPDATE live_sessions SET followers_count = GREATEST(followers_count + ?, 0) " \
      "WHERE id = ? RETURNING followers_count", delta.to_i, id
    ])
    count = self.class.connection.select_value(sql).to_i
    self.followers_count = count
    clear_attribute_change(:followers_count)
    count
  end

  private

  def assign_code
    return if code.present?
    5.times do
      candidate = self.class.random_code(CODE_LENGTH)
      unless self.class.exists?(code: candidate)
        self.code = candidate
        return
      end
    end
    self.code = self.class.random_code(FALLBACK_CODE_LENGTH)
  end
end
