# My Media — the account's picture library (MediaAsset), at /media.
#
#   GET    /media         the page (manage: upload, rename, default display,
#                         delete, storage used), or JSON for the console's
#                         My Media view (cached on the device for offline)
#   POST   /media         one picture (multipart `file`, optional title /
#                         width / height); the same file again returns the
#                         entry it already has (200, created: false)
#   PATCH  /media/:id     title and/or default display {fit, zoom}
#   DELETE /media/:id     out of the library; services that use it keep it
#
# The page answers with Turbo Streams, the console with JSON. Every query is
# scoped to the signed-in account — another account's id is a 404.
class MediaAssetsController < ApplicationController
  allow_unauthenticated_access only: %i[ index create update destroy ]
  before_action :require_account, except: :index
  before_action :set_asset, only: %i[ update destroy ]

  rate_limit to: 120, within: 10.minutes, only: :create, name: "media-upload",
             by: -> { Current.user&.id || request.remote_ip },
             with: -> { render_error("You're uploading very quickly — wait a minute and try again", :too_many_requests) }

  def index
    respond_to do |format|
      format.html do
        @assets = authenticated? ? library.with_attached_file.to_a : []
        @counts = MediaAsset.service_counts(@assets)
      end
      format.json do
        next head(:unauthorized) unless authenticated?
        assets = library.with_attached_file.to_a
        counts = MediaAsset.service_counts(assets)
        render json: { assets: assets.map { |a| a.as_library_json(services: counts[a.id] || 0) }, **storage }
      end
    end
  end

  def create
    result = MediaLibrary.add(current_user, params[:file], title: params[:title],
                              width: params[:width], height: params[:height])
    return render_error(result.message) unless result.ok?

    @asset = result.asset
    @created = result.created
    @count = MediaAsset.service_counts([ @asset ])[@asset.id] || 0
    respond_to do |format|
      format.turbo_stream
      format.json do
        render json: { asset: @asset.as_library_json(services: @count), created: @created, **storage },
               status: @created ? :created : :ok
      end
    end
  end

  def update
    changes = {}
    changes[:title] = params[:title] if params.key?(:title)
    if params.key?(:fit) || params.key?(:zoom)
      changes[:display] = @asset.display_settings.merge({ "fit" => params[:fit], "zoom" => params[:zoom] }.compact)
    end
    return render_error(@asset.errors.full_messages.to_sentence) unless @asset.update(changes)

    @count = MediaAsset.service_counts([ @asset ])[@asset.id] || 0
    respond_to do |format|
      format.turbo_stream
      format.json { render json: { asset: @asset.as_library_json(services: @count) } }
    end
  end

  def destroy
    @asset.destroy
    respond_to do |format|
      format.turbo_stream
      format.json { render json: storage }
    end
  end

  private

  def library = current_user.media_assets.recent_first

  def set_asset
    @asset = current_user.media_assets.find(params[:id])
  end

  def storage
    { used_bytes: MediaAsset.bytes_used(current_user), quota_bytes: MediaAsset::QUOTA_BYTES }
  end
  helper_method :storage

  def require_account
    return if authenticated?
    respond_to do |format|
      format.html { redirect_to new_session_path }
      format.any { head :unauthorized }
    end
  end

  def render_error(message, status = :unprocessable_entity)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update("media-status", html: message), status: status
      end
      format.any { render json: { error: message }, status: status }
    end
  end
end
