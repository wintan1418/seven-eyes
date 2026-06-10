# A live "follow along" broadcast for a study's preach mode. The pastor goes
# live and gets a short join code; congregants open /live/CODE on their phones
# and the current passage follows the pulpit in real time over Action Cable.
#
# State columns mirror what the operator last projected: book (OSIS) + chapter,
# the emphasised verse range, and the translation code. `followers_count` is
# adjusted by LiveSessionChannel as phones subscribe/unsubscribe.
class LiveSession < ApplicationRecord
  belongs_to :study

  # No 0/O, 1/I/L — the code gets read aloud and typed from the back pew.
  CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789".chars.freeze
  CODE_LENGTH = 4

  before_validation :assign_code, on: :create
  validates :code, presence: true, uniqueness: true

  scope :active, -> { where(ended_at: nil) }

  def self.find_active(code)
    active.find_by(code: code.to_s.upcase)
  end

  def ended? = ended_at.present?

  def end!
    update!(ended_at: Time.current) unless ended?
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

  def adjust_followers(delta)
    self.class.update_counters(id, followers_count: delta)
    reload
    update_column(:followers_count, 0) if followers_count.negative?
    followers_count
  end

  private

  def assign_code
    return if code.present?
    5.times do
      candidate = Array.new(CODE_LENGTH) { CODE_ALPHABET.sample }.join
      unless self.class.exists?(code: candidate)
        self.code = candidate
        return
      end
    end
    self.code = SecureRandom.alphanumeric(8).upcase
  end
end
