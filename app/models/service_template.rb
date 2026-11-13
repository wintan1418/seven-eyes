# A whole service order kept for reuse ("Sunday Service", "Midweek"): a
# snapshot of the queue's items. Applied to a queue on the device (offline) or
# used to start a new service (a new study with the queue filled in).
# Pictures are left out — their files belong to the queue they were uploaded to.
class ServiceTemplate < ApplicationRecord
  LIMIT = 50 # per account
  MAX_ITEMS = 150
  KINDS = (SetlistItem.kinds.keys - %w[ picture ]).freeze

  belongs_to :user

  normalizes :name, with: ->(n) { n.to_s.squish }

  validates :name, presence: true, length: { maximum: 80 }
  validates :client_id, presence: true, length: { maximum: 64 }, format: { with: /\A[\w-]+\z/ }
  validate :within_limit, on: :create

  before_validation :tidy_items

  scope :recent_first, -> { order(updated_at: :desc) }

  def self.save_for!(user, client_id, attrs)
    template = user.service_templates.find_or_initialize_by(client_id: client_id.to_s)
    template.assign_attributes(attrs)
    template.save!
    template
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  # A new study for `user` with this order in its queue. Items that no longer
  # validate (say, a reference the parser has since stopped reading) are skipped.
  def start!(date: Date.current)
    transaction do
      study = user.studies.create!(name: "#{name} — #{date.strftime('%-d %b %Y')}", pane_count: 1)
      first_scripture = items.find { |i| i["kind"] == "scripture" }
      study.panes.first&.update(reference: first_scripture["reference"]) if first_scripture
      items.each { |attrs| SetlistItem.create(attrs.slice("kind", "reference", "title", "body", "arrangement", "data").merge(study: study)) }
      study
    end
  end

  def as_device_json
    { id: client_id, name: name, items: items, updated_at: updated_at&.iso8601 }
  end

  private

  def tidy_items
    self.items = Array(items).first(MAX_ITEMS).filter_map do |raw|
      item = SlideData.hashify(raw)
      kind = item["kind"].to_s
      next unless KINDS.include?(kind)
      {
        "kind" => kind,
        "reference" => item["reference"].to_s[0, 200].presence,
        "title" => item["title"].to_s[0, 300].presence,
        "body" => item["body"].to_s[0, 40_000].presence,
        "arrangement" => item["arrangement"].to_s[0, 200].presence,
        "data" => SlideData.clean(kind, item["data"]).presence
      }.compact
    end
  end

  def within_limit
    errors.add(:base, "You can keep up to #{LIMIT} service templates") if user && user.service_templates.count >= LIMIT
  end
end
