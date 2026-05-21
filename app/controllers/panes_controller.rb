class PanesController < ApplicationController
  def update
    study = current_user.studies.find(params[:study_id])
    @pane = study.panes.find(params[:id])
    @pane.update(pane_params)
    render partial: "panes/pane", locals: { pane: @pane }
  end

  private

  def pane_params
    params.require(:pane).permit(:reference, :translation_id, :notes)
  end
end
