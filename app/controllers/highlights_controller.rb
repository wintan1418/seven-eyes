class HighlightsController < ApplicationController
  # Open the route so guests get a clean 401 (handled in JS) instead of an HTML redirect.
  allow_unauthenticated_access only: %i[ create destroy ]
  before_action :require_account

  def create
    highlight = current_user.highlights.create!(
      verse_id: params.dig(:highlight, :verse_id),
      color: params.dig(:highlight, :color),
      char_start: params.dig(:highlight, :char_start),
      char_end: params.dig(:highlight, :char_end)
    )
    render json: { id: highlight.id, color: highlight.color }, status: :created
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound
    head :unprocessable_entity
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
end
