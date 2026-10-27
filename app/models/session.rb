class Session < ApplicationRecord
  # A sign-in lasts this long; after that the user signs in again.
  TTL = 30.days

  belongs_to :user

  scope :active, -> { where(created_at: TTL.ago..) }

  def expired? = created_at < TTL.ago
end
