# The preach queue ("setlist"): scripture references, songs, and thoughts the
# operator lines up before the service and walks through from the preach bar.
# Every action re-renders the queue's Turbo Frame; guests can build a queue on
# their session study (current_study resolves owner-or-guest).
class SetlistItemsController < ApplicationController
  allow_unauthenticated_access

  before_action :set_study

  def create
    item = @study.setlist_items.create(item_params)
    @errored = item unless item.persisted?
    render_setlist
  end

  def update
    item.update(item_params)
    render_setlist
  end

  def destroy
    item.destroy
    render_setlist
  end

  # POST /studies/:study_id/setlist_items/:id/move?direction=up|down
  def move
    item.move!(params[:direction])
    render_setlist
  end

  private

  def set_study
    @study = current_study(params[:study_id])
  end

  def item
    @item ||= @study.setlist_items.find(params[:id])
  end

  def item_params
    params.require(:setlist_item).permit(:kind, :reference, :title, :body)
  end

  def render_setlist
    render partial: "studies/setlist", locals: { study: @study, errored: @errored }, layout: false
  end
end
