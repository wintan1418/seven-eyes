class Translation < ApplicationRecord
  has_many :verses, dependent: :destroy

  validates :code, presence: true, uniqueness: true
  validates :name, presence: true

  default_scope { order(:id) }

  def to_param = code
end
