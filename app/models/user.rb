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
  has_many :daily_completions, dependent: :delete_all

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true,
            format: { with: URI::MailTo::EMAIL_REGEXP, message: "must be a valid email" }
  validates :password, length: { minimum: 8 }, allow_nil: true
  validates :font_size, inclusion: { in: 0..4 }

  # May read draft glossary terms and review them (/admin/faith): admins, and
  # pastors flagged with `bin/rails reviewer:grant EMAIL=...`.
  def faith_reviewer? = admin? || reviewer?

  # Pastor mode puts "This Sunday" (the next service's order, readiness and
  # Present) at the top of Home. Unset, it follows what the account does:
  # anyone who has lined up a service queue or gone live is a preacher.
  def pastor_mode?
    pastor_mode.nil? ? preacher? : pastor_mode
  end

  def preacher?
    return @preacher if defined?(@preacher)

    @preacher = SetlistItem.joins(:study).where(studies: { user_id: id }).exists? ||
      LiveSession.joins(:study).where(studies: { user_id: id }).exists?
  end

  # Accounts carry no name, only an email. The home greeting uses the email's
  # first word when it reads like a name ("grace.okafor@…" → "Grace") and
  # nothing otherwise ("info@…", "a1@…").
  NOT_A_NAME = %w[ info admin contact hello office church mail email user test team support ministry pastor ].freeze

  def greeting_name
    word = email_address.to_s.split("@").first.to_s.split(/[._+\-]/).first.to_s.gsub(/\d+/, "")
    return nil unless word.match?(/\A[a-z]{2,20}\z/i) && NOT_A_NAME.exclude?(word.downcase)
    word.capitalize
  end
end
