# Adds pictures to an account's My Media library (MediaAsset) — from the
# /media page, the console's My Media view, or a picture added to a service
# through the queue form. The same file twice is one library entry: the file's
# checksum is worked out before anything is uploaded, and a match is returned
# as it is (nothing uploaded, nothing stored again).
#
#   MediaLibrary.add(user, uploaded_file, title: nil, width: nil, height: nil)
#     → Result(ok?, asset, created, error) — error is a PictureUpload error key
#       or :full (the account's QUOTA_BYTES would be passed)
class MediaLibrary
  Result = Struct.new(:ok, :asset, :created, :error, keyword_init: true) do
    def ok? = ok
    def message = MediaLibrary.message_for(error)
  end

  def self.message_for(error)
    return "Your picture library is full (#{ActiveSupport::NumberHelper.number_to_human_size(MediaAsset::QUOTA_BYTES)}) — delete pictures you no longer use in My Media" if error == :full
    PictureUpload.message_for(error)
  end

  def self.add(user, file, title: nil, width: nil, height: nil)
    new(user).add(file, title: title, width: width, height: height)
  end

  def initialize(user)
    @user = user
  end

  def add(file, title: nil, width: nil, height: nil)
    refused = PictureUpload.refusal(file)
    return failure(refused) if refused

    checksum = PictureUpload.checksum(file)
    existing = @user.media_assets.find_by(checksum: checksum)
    return Result.new(ok: true, asset: existing, created: false) if existing
    return failure(:full) if MediaAsset.bytes_used(@user) + file.size.to_i > MediaAsset::QUOTA_BYTES

    upload = PictureUpload.call(file)
    return failure(upload.error) unless upload.ok?

    asset = @user.media_assets.create!(
      title: title.presence || MediaAsset.title_from_filename(file.original_filename),
      checksum: upload.blob&.checksum || checksum, byte_size: file.size.to_i,
      content_type: file.content_type, width: dimension(width), height: dimension(height),
      media_url: upload.url, media_public_id: upload.public_id, file: upload.blob
    )
    Result.new(ok: true, asset: asset, created: true)
  rescue ActiveRecord::RecordNotUnique
    # The same picture finished uploading in another request a moment ago.
    discard(upload)
    Result.new(ok: true, asset: @user.media_assets.find_by!(checksum: checksum), created: false)
  rescue ActiveRecord::RecordInvalid => e
    discard(upload)
    Rails.logger.error("[MediaLibrary] #{e.message}")
    failure(:api)
  end

  private

  # An upload no library entry ended up keeping.
  def discard(upload)
    return unless upload
    upload.blob&.purge_later
    PictureUpload.purge_unused(upload.public_id)
  end

  def failure(error) = Result.new(ok: false, error: error)

  def dimension(value)
    n = value.to_s[/\A\d{1,5}\z/]&.to_i
    n&.positive? ? n : nil
  end
end
