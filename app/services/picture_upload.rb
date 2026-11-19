require "cloudinary"

# Uploads a queue picture (announcement slide, sermon graphic) to Cloudinary
# and returns its CDN URL. Safety limits enforced BEFORE any network call:
# images only, max 5 MB, and Cloudinary itself stores at most 1920×1080.
#
# Config: the standard CLOUDINARY_URL env var (cloudinary://key:secret@cloud),
# or the CLOUDINARY_CLOUD_NAME / CLOUDINARY_API_KEY / CLOUDINARY_API_SECRET trio.
class PictureUpload
  MAX_BYTES = 5.megabytes
  FOLDER = "bibliorata/queue".freeze

  Result = Struct.new(:ok, :url, :public_id, :error, :blob, keyword_init: true) do
    def ok? = ok
  end

  ERROR_MESSAGES = {
    missing: "Choose a picture to upload",
    not_image: "That file isn't a picture — JPG, PNG, or WebP please",
    too_large: "That picture is over 5 MB — export it smaller and try again",
    no_config: "Picture hosting isn't configured yet (set CLOUDINARY_URL)",
    api: "The picture host didn't accept the upload — try again"
  }.freeze

  def self.message_for(error) = ERROR_MESSAGES[error] || ERROR_MESSAGES[:api]

  def self.configured?
    return false if Rails.env.test? # never touch the network from the test suite
    ENV["CLOUDINARY_URL"].present? ||
      (ENV["CLOUDINARY_CLOUD_NAME"].present? && ENV["CLOUDINARY_API_KEY"].present? &&
       ENV["CLOUDINARY_API_SECRET"].present?)
  end

  def self.call(file) = new(file).call

  # Why this file can't be a queue / library picture (an ERROR_MESSAGES key),
  # or nil. Checked before anything is hashed or uploaded.
  def self.refusal(file)
    return :missing if file.blank? || !file.respond_to?(:tempfile)
    return :not_image unless file.content_type.to_s.start_with?("image/")
    :too_large if file.size.to_i > MAX_BYTES
  end

  # The file's MD5, base64 — the same value Active Storage keeps as the blob's
  # checksum, so a picture already in My Media is found before any upload.
  def self.checksum(file)
    io = file.tempfile
    io.rewind
    digest = OpenSSL::Digest::MD5.new
    buffer = "".b
    digest << buffer while io.read(1.megabyte, buffer)
    io.rewind
    digest.base64digest
  end

  # A Cloudinary copy is shared by every queue item and the My Media entry
  # made from the same upload: destroy it only once none of them names it.
  def self.purge_unused(public_id)
    return if public_id.blank?
    return if SetlistItem.exists?(media_public_id: public_id) || MediaAsset.exists?(media_public_id: public_id)
    purge(public_id)
  end

  # Best-effort remote delete when a picture leaves the queue.
  def self.purge(public_id)
    return if public_id.blank? || !configured?
    configure!
    Cloudinary::Uploader.destroy(public_id)
  rescue => e
    Rails.logger.warn("[PictureUpload] purge failed: #{e.class}: #{e.message}")
  end

  def self.configure!
    return if ENV["CLOUDINARY_URL"].present? # the gem reads this itself
    Cloudinary.config do |c|
      c.cloud_name = ENV["CLOUDINARY_CLOUD_NAME"]
      c.api_key = ENV["CLOUDINARY_API_KEY"]
      c.api_secret = ENV["CLOUDINARY_API_SECRET"]
      c.secure = true
    end
  end

  def initialize(file)
    @file = file
  end

  def call
    refused = self.class.refusal(@file)
    return err(refused) if refused
    return store_locally unless self.class.configured?

    begin
      res = upload
      Result.new(ok: true, url: res["secure_url"], public_id: res["public_id"])
    rescue => e
      # The host refused (e.g. "cloud_name is disabled"): keep the picture on
      # our own server so the service can still show it.
      Rails.logger.error("[PictureUpload] #{e.class}: #{e.message} — storing locally")
      store_locally
    end
  end

  private

  def err(code) = Result.new(ok: false, error: code)

  # Saved with Active Storage on this server. The blob is attached to the
  # queue item by the controller (SetlistItem#picture_file).
  def store_locally
    @file.tempfile.rewind
    blob = ActiveStorage::Blob.create_and_upload!(
      io: @file.tempfile,
      filename: @file.original_filename.presence || "picture",
      content_type: @file.content_type
    )
    url = Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true)
    Result.new(ok: true, url: url, public_id: nil, blob: blob)
  rescue => e
    Rails.logger.error("[PictureUpload] local store failed: #{e.class}: #{e.message}")
    err(:api)
  end

  # Network seam — overridden in tests. The incoming transformation caps what
  # Cloudinary stores, so even a huge photo lands as a projector-sized asset.
  def upload
    self.class.configure!
    Cloudinary::Uploader.upload(
      @file.tempfile,
      folder: FOLDER,
      resource_type: "image",
      transformation: [ { width: 1920, height: 1080, crop: "limit" } ]
    )
  end
end
