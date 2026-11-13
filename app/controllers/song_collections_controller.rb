# The song bank's collections (JSON, from the song_bank controller via the
# outbox). The device names each collection (its client_id is the :id here)
# and sends the whole thing every time, so a replayed change is harmless.
# Guests get a clean 401 — the page opens the "create an account" gate.
class SongCollectionsController < ApplicationController
  allow_unauthenticated_access only: %i[ update destroy ]
  before_action :require_account

  # PUT /song_collections/:id {song_collection: {name, titles: […]}}
  def update
    collection = SongCollection.save_for!(current_user, params[:id], collection_params)
    render json: collection.as_device_json
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  # DELETE /song_collections/:id
  def destroy
    current_user.song_collections.find_by(client_id: params[:id].to_s)&.destroy
    head :no_content
  end

  private

  def collection_params
    params.require(:song_collection).permit(:name, titles: [])
  end

  def require_account
    head :unauthorized unless authenticated?
  end
end
