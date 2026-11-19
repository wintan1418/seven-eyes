# My Media — the account's picture library (MediaAsset), as JSON for the
# operator console's My Media view (console_media controller):
#
#   GET  /media   the account's pictures, last used first, with how many of its
#                 services use each, and the storage used / allowed
#   POST /media   one picture (multipart `file`, optional title / width /
#                 height); the same file again returns the entry it already
#                 has (200, created: false) — nothing is stored twice
#
# Every query is scoped to the signed-in account; guests get a 401.
class MediaAssetsController < ApplicationController
  allow_unauthenticated_access only: %i[ index create ]
  before_action :require_account

  rate_limit to: 120, within: 10.minutes, only: :create, name: "media-upload",
             by: -> { Current.user&.id || request.remote_ip },
             with: -> { render json: { error: "You're uploading very quickly — wait a minute and try again" }, status: :too_many_requests }

  def index
    assets = current_user.media_assets.recent_first.with_attached_file.to_a
    counts = MediaAsset.service_counts(assets)
    render json: { assets: assets.map { |a| a.as_library_json(services: counts[a.id] || 0) }, **storage }
  end

  def create
    result = MediaLibrary.add(current_user, params[:file], title: params[:title],
                              width: params[:width], height: params[:height])
    return render(json: { error: result.message }, status: :unprocessable_entity) unless result.ok?

    asset = result.asset
    count = MediaAsset.service_counts([ asset ])[asset.id] || 0
    render json: { asset: asset.as_library_json(services: count), created: result.created, **storage },
           status: result.created ? :created : :ok
  end

  private

  def storage
    { used_bytes: MediaAsset.bytes_used(current_user), quota_bytes: MediaAsset::QUOTA_BYTES }
  end

  def require_account
    head :unauthorized unless authenticated?
  end
end
