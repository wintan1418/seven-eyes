# Glossary of the Faith: one core word of the Christian faith (Grace,
# Justification, Covenant …) explained in plain English, with its Greek /
# Hebrew root words (Strong's numbers → LexiconEntry) and key verses read from
# our own Bible text.
#
# Separate from DailyWord ("Word for Today"): that is a *passage* a day with an
# AI reflection; this is a hand-written, pastor-reviewed *term* a day.
#
# Review gate: every term starts as a draft. The public only ever sees reviewed
# terms (FaithTerm.visible_to); admins and reviewers (User#faith_reviewer?) see
# drafts too, badged "Draft — awaiting pastor review". With no reviewed terms the
# home card, the glossary and its menu links simply don't appear.
class FaithTerm < ApplicationRecord
  # Same calendar as the Word for Today, so the home screen turns over once.
  EPOCH = Date.new(2026, 1, 1)
  STRONGS_FORMAT = /\A[GH]\d{1,4}\z/
  SLUG_FORMAT = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
  MAX_REFERENCES = 6

  enum :status, { draft: 0, reviewed: 1 }, default: :draft, validate: true

  normalizes :root_strongs, with: ->(list) { Array(list).map { |s| s.to_s.strip.upcase }.compact_blank.uniq }
  normalizes :key_references, with: ->(list) { Array(list).map { |s| s.to_s.squish }.compact_blank.uniq }
  normalizes :related_slugs, with: ->(list) { Array(list).map { |s| s.to_s.strip.parameterize }.compact_blank.uniq }
  normalizes :aliases, with: ->(list) { Array(list).map { |s| s.to_s.squish }.compact_blank.uniq }

  before_validation :default_slug

  validates :name, :short_definition, presence: true
  validates :slug, presence: true, uniqueness: true, format: { with: SLUG_FORMAT }
  validate :root_strongs_look_right
  validate :key_references_parse

  scope :in_order, -> { order(:position, :id) }
  scope :alphabetical, -> { order(Arel.sql("LOWER(faith_terms.name)")) }

  class << self
    # What a viewer may see: reviewed terms, or everything for a reviewer.
    def visible_to(user)
      user&.faith_reviewer? ? all : reviewed
    end

    # The term for a date: a fixed walk through `scope` in position order, so
    # everyone sees the same term on the same day. nil when scope is empty.
    def of_the_day(date = DailyWord.today_date, scope: reviewed)
      ids = scope.in_order.pluck(:id)
      return nil if ids.empty?

      scope.find(ids[(date - EPOCH).to_i % ids.size])
    end
  end

  def to_param = slug

  def mark_reviewed!(by:)
    update!(status: :reviewed, reviewed_by: by.to_s.squish.presence, reviewed_at: Time.current)
  end

  def send_back_to_draft!
    update!(status: :draft, reviewed_by: nil, reviewed_at: nil)
  end

  # The lexicon entries for root_strongs, in the order given; numbers the
  # lexicon doesn't have (not seeded yet, or a typo) are left out.
  def root_entries
    found = LexiconEntry.where(strongs: root_strongs).index_by(&:strongs)
    root_strongs.filter_map { |s| found[s] }
  end

  # Related terms the viewer may see, in the order listed.
  def related_terms(scope = FaithTerm.reviewed)
    found = scope.where(slug: related_slugs).index_by(&:slug)
    related_slugs.filter_map { |s| found[s] }
  end

  # Lower-case words the glossary search matches against.
  def search_text
    [ name, *aliases, short_definition ].join(" ").downcase.squish
  end

  def letter = name.to_s.strip.first.to_s.upcase

  private

  def default_slug
    self.slug = name.to_s.parameterize if slug.blank? && name.present?
  end

  def root_strongs_look_right
    bad = root_strongs.grep_v(STRONGS_FORMAT)
    errors.add(:root_strongs, "don't look like Strong's numbers: #{bad.join(', ')}") if bad.any?
  end

  def key_references_parse
    errors.add(:key_references, "can be at most #{MAX_REFERENCES}") if key_references.size > MAX_REFERENCES
    bad = key_references.reject do |ref|
      parsed = ReferenceParser.call(ref)
      parsed.valid? && parsed.verse_start
    end
    errors.add(:key_references, "couldn't be read: #{bad.join('; ')}") if bad.any?
  end
end
