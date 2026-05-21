class PanesController < ApplicationController
  # Guests may navigate Scripture (reference/translation); only notes require an account.
  allow_unauthenticated_access only: %i[ update ]

  def update
    study = current_study(params[:study_id])
    @pane = study.panes.find(params[:id])

    # Saving notes is a "save" — require an account.
    return head(:unauthorized) if params[:autosave] && !authenticated?

    @pane.update(pane_params)

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
