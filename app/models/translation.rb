class Translation < ApplicationRecord
  has_many :verses, dependent: :destroy

  validates :code, presence: true, uniqueness: true
  validates :name, presence: true

  default_scope { order(:id) }

  DEFAULT_CODE = "KJV".freeze

  # A translation with fewer verses than this is a broken/partial seed (the
  # Protestant canon has ~31,100). Not offered until it is re-seeded.
  COMPLETE_VERSE_COUNT = 30_000

  # Translations numbered after the Latin Vulgate rather than the Hebrew/English
  # tradition: their Psalm 22 is everyone else's Psalm 23, and so on.
  VULGATE_NUMBERING = %w[DRA].freeze

  # What readers may choose: not licence-restricted, and completely seeded.
  # verse_count is stamped by BibleSeeder (and backfilled by migration); NULL
  # means "never counted" (rows made by hand, e.g. in tests) and is trusted.
  scope :available, -> {
    where.not(code: BibleSeeder::RESTRICTED)
         .where("translations.verse_count IS NULL OR translations.verse_count >= ?", COMPLETE_VERSE_COUNT)
  }

  # The translation to fall back to: KJV when offered, else the first offered.
  def self.default
    available.find_by(code: DEFAULT_CODE) || available.first
  end

  def available? = self.class.available.exists?(id)

  def vulgate_numbering? = VULGATE_NUMBERING.include?(code)

  # Name for menus and headings; flags Vulgate psalm/chapter numbering.
  def display_name
    vulgate_numbering? ? "#{name} (Vulgate numbering)" : name
  end

  def to_param = code
end
