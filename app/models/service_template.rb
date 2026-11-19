# A whole service order kept for reuse ("Sunday Service", "Midweek"): a
# snapshot of the queue's items. Applied to a queue on the device (offline) or
# used to start a new service (a new study with the queue filled in).
# Pictures are kept by their My Media entry ({kind: "picture", media_asset_id,
# title, data}) — only the account's own entries; one deleted from My Media
# since is skipped when the template is used. Passages pasted from the pastor's
# own Bible ("Paste your own" — NKJV, NIV…) are deliberately left out: they
# belong to one sermon, and the quotation allowance they rely on is per use.
class ServiceTemplate < ApplicationRecord
  LIMIT = 50 # per account
  MAX_ITEMS = 150
  KINDS = SetlistItem.kinds.keys.freeze

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
      assets = library_assets
      items.each do |attrs|
        if attrs["kind"] == "picture"
          asset = assets[attrs["media_asset_id"]]
          next unless asset
          picture = SetlistItem.picture_attrs_from(asset)
          picture[:title] = attrs["title"] if attrs["title"].present?
          picture[:data] = attrs["data"] if attrs["data"].present?
          study.setlist_items.create(picture)
        else
          SetlistItem.create(attrs.slice("kind", "reference", "title", "body", "arrangement", "data").merge(study: study))
        end
      end
      study
    end
  end

  # Pictures carry their library file's URL (so "Add to this queue" shows and
  # projects them on the device, offline too); ones no longer in My Media drop out.
  def as_device_json
    assets = library_assets
    list = items.filter_map do |item|
      next item unless item["kind"] == "picture"
      asset = assets[item["media_asset_id"]]
      asset && item.merge("image" => asset.media_url, "thumb" => asset.thumb_url)
    end
    { id: client_id, name: name, items: list, updated_at: updated_at&.iso8601 }
  end

  # The owner's My Media entries this template's pictures use, by id.
  def library_assets
    ids = items.filter_map { |i| i["media_asset_id"] if i["kind"] == "picture" }
    return {} if ids.empty? || !user
    user.media_assets.where(id: ids).with_attached_file.index_by(&:id)
  end

  private

  def tidy_items
    raw_items = Array(items).first(MAX_ITEMS).map { |raw| SlideData.hashify(raw) }
    owned = owned_asset_ids(raw_items)
    self.items = raw_items.filter_map do |item|
      kind = item["kind"].to_s
      next unless KINDS.include?(kind)
      next picture_entry(item, owned) if kind == "picture"
      next if kind == "scripture_set" && SlideData.own?(SlideData.clean(kind, item["data"]))
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

  # A picture is kept only as one of the owner's own My Media entries.
  def picture_entry(item, owned)
    id = item["media_asset_id"].to_s[/\A\d{1,18}\z/]&.to_i
    return nil unless id && owned.include?(id)
    {
      "kind" => "picture", "media_asset_id" => id,
      "title" => item["title"].to_s.squish[0, 120].presence,
      "data" => SlideData.picture(SlideData.hashify(item["data"]))
    }.compact
  end

  def owned_asset_ids(raw_items)
    ids = raw_items.filter_map { |i| i["media_asset_id"].to_s[/\A\d{1,18}\z/]&.to_i if i["kind"].to_s == "picture" }
    return Set.new if ids.empty? || !user
    user.media_assets.where(id: ids).pluck(:id).to_set
  end

  def within_limit
    errors.add(:base, "You can keep up to #{LIMIT} service templates") if user && user.service_templates.count >= LIMIT
  end
end
