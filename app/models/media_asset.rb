# One picture in an account's My Media library: a flyer, photo or sermon
# graphic the pastor uploads once and uses in any service, on any computer.
#
# The file is the same one the queue uses (Active Storage on our server, or a
# Cloudinary URL from before), kept once per account: the same file added
# again — to the library or to any service — finds this row by its checksum
# and nothing is uploaded twice. `display` is how it fills the screen by
# default (fit / fill / stretch + zoom, SlideData.picture); each queue item
# that uses it keeps its own copy of that, changed per service.
#
# Deleting it from the library never takes it out of a service: queue items
# hold their own attachment to the same blob (and their own URL), so the file
# stays until nothing uses it (the blob's foreign key stops a purge while it is
# attached anywhere; a Cloudinary copy is only destroyed once no item or
# library entry names it — PictureUpload.purge_unused).
class MediaAsset < ApplicationRecord
  QUOTA_BYTES = 1.gigabyte # per account
  THUMB_SIZE = [ 480, 270 ].freeze

  belongs_to :user
  has_many :setlist_items, dependent: :nullify
  has_one_attached :file do |attachable|
    attachable.variant :thumb, resize_to_limit: THUMB_SIZE
  end

  normalizes :title, with: ->(t) { t.to_s.squish }

  validates :title, presence: true, length: { maximum: 120 }
  validates :media_url, presence: true, length: { maximum: 2_000 }
  validates :width, :height, numericality: { only_integer: true, greater_than: 0, less_than: 100_000 }, allow_nil: true

  before_validation { self.display = SlideData.picture(display) }
  after_destroy_commit { PictureUpload.purge_unused(media_public_id) }

  scope :recent_first, -> { order(Arel.sql("COALESCE(media_assets.last_used_at, media_assets.created_at) DESC"), id: :desc) }

  def self.bytes_used(user) = where(user: user).sum(:byte_size)

  # "Sunday flyer.final.JPG" → "Sunday flyer.final"
  def self.title_from_filename(name)
    base = File.basename(name.to_s, File.extname(name.to_s)).tr("_", " ").squish
    base.presence&.truncate(120, omission: "") || "Picture"
  end

  # How it fills the screen by default: { "fit" => …, "zoom" => … }.
  def display_settings = SlideData.picture(display)

  def used!
    update_column(:last_used_at, Time.current)
  end

  # A small picture for grids (the console's My Media, the /media page):
  # Cloudinary resizes by URL; our own files get an Active Storage variant
  # only where libvips is installed (production may not have it — then the
  # grid shows the picture itself, lazy-loaded, rather than a request that
  # fails on every card).
  def thumb_url
    if cloudinary?
      media_url.sub("/upload/", "/upload/c_limit,w_#{THUMB_SIZE[0]},h_#{THUMB_SIZE[1]}/")
    elsif file.attached? && file.variable? && self.class.thumbnails?
      Rails.application.routes.url_helpers.rails_representation_path(file.variant(:thumb), only_path: true)
    else
      media_url
    end
  end

  def cloudinary? = media_url.to_s.start_with?("https://res.cloudinary.com/") && media_url.include?("/upload/")

  # Can this server make thumbnails? (ruby-vips raises LoadError when the
  # libvips library isn't installed.) Checked once per process.
  def self.thumbnails?
    return @thumbnails if defined?(@thumbnails)
    @thumbnails = begin
      require "vips"
      true
    rescue LoadError
      Rails.logger.info("[MediaAsset] libvips not available — grids show the pictures themselves")
      false
    end
  end

  # Tests flip this.
  def self.thumbnails=(value)
    @thumbnails = value
  end

  def pixel_width = width || file_metadata("width")
  def pixel_height = height || file_metadata("height")

  # What the console's My Media view and the /media page work with.
  # `services` — how many of the owner's services use it (preloaded counts).
  def as_library_json(services: nil)
    {
      id: id, title: title, url: media_url, thumb: thumb_url, display: display_settings,
      width: pixel_width, height: pixel_height, byte_size: byte_size, content_type: content_type,
      services: services, created_at: created_at&.iso8601
    }.compact
  end

  # { asset_id => number of distinct services using it } for these assets.
  def self.service_counts(assets)
    ids = Array(assets).map(&:id)
    return {} if ids.empty?
    SetlistItem.where(media_asset_id: ids).group(:media_asset_id).distinct.count(:study_id)
  end

  private

  def file_metadata(key)
    file.attached? ? file.blob.metadata[key]&.to_i : nil
  end
end
