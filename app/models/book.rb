class Book < ApplicationRecord
  has_many :verses, dependent: :destroy

  enum :testament, { old: 0, new: 1 }, prefix: true

  validates :osis_code, presence: true, uniqueness: true
  validates :name, presence: true
  validates :position, presence: true, uniqueness: true
  validates :chapter_count, presence: true

  default_scope { order(:position) }

  def self.find_by_osis(code)
    find_by(osis_code: code)
  end
end
