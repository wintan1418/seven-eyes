class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :studies, dependent: :destroy
  has_many :highlights, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true,
            format: { with: URI::MailTo::EMAIL_REGEXP, message: "must be a valid email" }
  validates :password, length: { minimum: 8 }, allow_nil: true
end
