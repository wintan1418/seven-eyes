# Collects the pictures already in signed-in users' services into their My
# Media libraries. Run by the BackfillMediaAssets migration and by
# `bin/rails media:backfill` (safe to run again at any time):
#
#   • idempotent — only queue pictures with no library entry yet are looked
#     at, and an entry is found before one is made (per user: by the blob's
#     checksum, else the Cloudinary public id, else the URL);
#   • batched — BATCH items at a time, each batch in its own transaction;
#   • no file is read, copied or uploaded: the library entry attaches the
#     queue item's own blob (or keeps its Cloudinary URL), so it costs rows,
#     not storage. Guests' studies (no user) are left alone.
#
# Returns { linked:, created:, skipped: } counts.
class MediaBackfill
  BATCH = 200

  def self.run(logger: Rails.logger) = new(logger).run

  def initialize(logger)
    @logger = logger
    @stats = { linked: 0, created: 0, skipped: 0 }
  end

  def run
    pending.in_batches(of: BATCH) do |batch|
      items = batch.includes(:study, picture_file_attachment: :blob).order(:created_at, :id).to_a
      MediaAsset.transaction { items.each { |item| collect(item) } }
    end
    @stats
  end

  private

  def pending
    SetlistItem.picture.where(media_asset_id: nil).where.not(media_url: [ nil, "" ])
               .where(study_id: Study.where.not(user_id: nil).select(:id))
  end

  def collect(item)
    user_id = item.study.user_id
    blob = item.picture_file.attached? ? item.picture_file.blob : nil
    asset = find_existing(user_id, item, blob) || create_for(user_id, item, blob)
    item.update_column(:media_asset_id, asset.id)
    stamp_last_used(asset, item)
    @stats[:linked] += 1
  rescue => e
    @stats[:skipped] += 1
    @logger&.warn("[MediaBackfill] setlist item #{item.id}: #{e.class}: #{e.message}")
  end

  def find_existing(user_id, item, blob)
    scope = MediaAsset.where(user_id: user_id)
    (blob&.checksum && scope.find_by(checksum: blob.checksum)) ||
      (item.media_public_id.present? && scope.find_by(media_public_id: item.media_public_id)) ||
      scope.find_by(media_url: item.media_url)
  end

  def create_for(user_id, item, blob)
    asset = MediaAsset.new(
      user_id: user_id,
      title: item.title.presence || (blob ? MediaAsset.title_from_filename(blob.filename.to_s) : "Picture"),
      checksum: blob&.checksum, byte_size: blob&.byte_size.to_i, content_type: blob&.content_type,
      media_url: item.media_url, media_public_id: item.media_public_id,
      display: item.picture_display, last_used_at: item.updated_at,
      created_at: item.created_at
    )
    asset.file.attach(blob) if blob
    asset.save!
    @stats[:created] += 1
    asset
  end

  def stamp_last_used(asset, item)
    return if asset.last_used_at && item.updated_at && asset.last_used_at >= item.updated_at
    asset.update_column(:last_used_at, item.updated_at)
  end
end
