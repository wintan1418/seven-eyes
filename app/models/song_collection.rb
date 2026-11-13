# One of the account's song bank collections ("Communion", "Christmas",
# "Choir"). Songs are listed by title, so a collection can hold hymnal songs as
# well as the account's own; the song bank matches them case-insensitively.
# The device names it (client_id) and always sends the whole collection, so a
# change made offline replays as an idempotent upsert (SongCollectionsController).
class SongCollection < ApplicationRecord
  LIMIT = 100 # per account
  MAX_SONGS = 500

  belongs_to :user

  normalizes :name, with: ->(n) { n.to_s.squish }

  validates :name, presence: true, length: { maximum: 60 }
  validates :client_id, presence: true, length: { maximum: 64 }, format: { with: /\A[\w-]+\z/ }
  validate :within_limit, on: :create

  before_validation :tidy_titles

  scope :in_order, -> { order(:created_at, :id) }

  def self.save_for!(user, client_id, attrs)
    collection = user.song_collections.find_or_initialize_by(client_id: client_id.to_s)
    collection.assign_attributes(attrs)
    collection.save!
    collection
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def as_device_json
    { id: client_id, name: name, titles: titles }
  end

  private

  def tidy_titles
    seen = {}
    self.titles = Array(titles).map { |t| t.to_s.squish[0, 200] }.reject(&:blank?)
                               .select { |t| seen[t.downcase] ? false : (seen[t.downcase] = true) }
                               .first(MAX_SONGS)
  end

  def within_limit
    errors.add(:base, "You can keep up to #{LIMIT} collections") if user && user.song_collections.count >= LIMIT
  end
end
