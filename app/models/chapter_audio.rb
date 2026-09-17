# One narrated chapter of Scripture (translation + book + chapter + voice),
# generated once by TTS and cached forever — the text never changes. The mp3
# lives in Active Storage; `status` tracks the background generation.
class ChapterAudio < ApplicationRecord
  belongs_to :translation
  belongs_to :book
  has_one_attached :audio

  enum :status, { pending: 0, ready: 1, failed: 2 }, default: :pending

  validates :chapter, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :chapter, uniqueness: { scope: %i[translation_id book_id voice] }

  scope :requested_today, -> { where(created_at: Time.current.all_day) }

  def playable? = ready? && audio.attached?
end
