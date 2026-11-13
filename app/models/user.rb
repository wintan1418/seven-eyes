class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :studies, dependent: :destroy
  has_many :highlights, dependent: :destroy
  has_many :songs, dependent: :delete_all
  has_many :song_collections, dependent: :delete_all
  has_many :service_templates, dependent: :delete_all
  has_many :reading_plans, dependent: :destroy
  has_many :ai_reports, dependent: :delete_all

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true,
            format: { with: URI::MailTo::EMAIL_REGEXP, message: "must be a valid email" }
  validates :password, length: { minimum: 8 }, allow_nil: true
  validates :font_size, inclusion: { in: 0..4 }

  # May read draft glossary terms and review them (/admin/faith): admins, and
  # pastors flagged with `bin/rails reviewer:grant EMAIL=...`.
  def faith_reviewer? = admin? || reviewer?
end
