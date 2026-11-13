# The account's own song bank (JSON, from the song editor's "Save to my songs"
# and the song bank's remove). Saving is by title, so the outbox can replay a
# save made offline without making a twin. Guests get a clean 401 — the page
# opens the "create an account to save" gate.
class SongsController < ApplicationController
  allow_unauthenticated_access only: %i[ create destroy ]
  before_action :require_account

  # POST /songs {song: {title, body, arrangement, author}}
  def create
    song = Song.save_for!(current_user, song_params)
    render json: song.as_library_json, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  # DELETE /songs/:id — or by title (?title=…) for a song saved offline whose id the device never heard.
  def destroy
    songs = current_user.songs
    song = params[:id].to_s.match?(/\A\d+\z/) ? songs.find_by(id: params[:id]) : songs.find_by("lower(title) = ?", params[:title].to_s.squish.downcase)
    song&.destroy
    head :no_content
  end

  private

  def song_params
    params.require(:song).permit(:title, :body, :arrangement, :author)
  end

  def require_account
    head :unauthorized unless authenticated?
  end
end
