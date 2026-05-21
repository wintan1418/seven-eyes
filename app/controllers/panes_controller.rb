class PanesController < ApplicationController
  def update
    study = current_user.studies.find(params[:study_id])
    @pane = study.panes.find(params[:id])
    @pane.update(pane_params)

    # Notes auto-save is a background fetch; don't re-render the whole pane frame.
    if params[:autosave]
      head :no_content
    else
      render partial: "panes/pane", locals: { pane: @pane }
    end
  end

  private

  def pane_params
    params.require(:pane).permit(:reference, :translation_id, :notes)
  end
end
