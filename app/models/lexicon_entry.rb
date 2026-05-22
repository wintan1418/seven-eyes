class LexiconEntry < ApplicationRecord
  validates :strongs, presence: true, uniqueness: true
  validates :language, presence: true

  scope :greek, -> { where(language: "greek") }
  scope :hebrew, -> { where(language: "hebrew") }

  def self.lookup(strongs)
    find_by(strongs: strongs.to_s.upcase)
  end
end
