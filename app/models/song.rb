# A song in the account's own song bank ("Save to my songs" in the song
# editor). The preach queue copies a song's words into its own SetlistItem, so
# editing the bank never changes a queue that's already planned. One per title
# per account: saving again under the same title updates it.
class Song < ApplicationRecord
  LIMIT = 2000 # per account

  belongs_to :user

  normalizes :title, with: ->(t) { t.to_s.squish }

  validates :title, presence: true, length: { maximum: 200 }
  validates :body, length: { maximum: 20_000 }
  validates :arrangement, length: { maximum: 200 }
  validates :author, length: { maximum: 200 }
  validate :within_limit, on: :create

  scope :recent_first, -> { order(updated_at: :desc) }

  # Save by title: the same title (any case) updates the song already there.
  def self.save_for!(user, attrs)
    song = user.songs.where("lower(title) = ?", attrs[:title].to_s.squish.downcase).first_or_initialize
    song.assign_attributes(attrs)
    song.save!
    song
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def as_library_json
    { id: id, title: title, body: body.to_s, arrangement: arrangement.to_s, author: author.presence, source: "yours", saved: true }.compact
  end

  private

  def within_limit
    errors.add(:base, "Your song bank is full (#{LIMIT} songs)") if user && user.songs.count >= LIMIT
  end
end
