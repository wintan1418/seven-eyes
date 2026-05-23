class HighlightsController < ApplicationController
  # Open the routes so guests get a clean 401 (handled in JS) instead of an HTML redirect.
  allow_unauthenticated_access only: %i[ create update destroy ]
  before_action :require_account

  def create
    highlight = current_user.highlights.create!(
      verse_id: params.dig(:highlight, :verse_id),
      color: params.dig(:highlight, :color),
      char_start: params.dig(:highlight, :char_start),
      char_end: params.dig(:highlight, :char_end),
      note: params.dig(:highlight, :note)
    )
    render json: highlight_payload(highlight), status: :created
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound
    head :unprocessable_entity
  end

  # Edit an existing highlight's note and/or color.
  def update
    highlight = current_user.highlights.find(params[:id])
    highlight.update!(params.require(:highlight).permit(:color, :note))
    render json: highlight_payload(highlight)
  rescue ActiveRecord::RecordInvalid
    head :unprocessable_entity
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def destroy
    current_user.highlights.find(params[:id]).destroy
    head :no_content
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  private

  def require_account
    head :unauthorized unless authenticated?
  end

  def highlight_payload(h)
    { id: h.id, color: h.color, note: h.note.to_s }
  end
end
