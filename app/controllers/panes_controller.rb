class PanesController < ApplicationController
  # Guests may navigate Scripture (reference/translation); only notes require an account.
  allow_unauthenticated_access only: %i[ update ]

  def update
    study = current_study(params[:study_id])
    @pane = study.panes.find(params[:id])

    # Writing notes is a "save" — it requires an account however it arrives
    # (the debounced autosave, a keepalive flush, or a full pane form).
    return head(:unauthorized) if writes_notes? && !authenticated?

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

  def writes_notes?
    params[:pane].respond_to?(:key?) && params[:pane].key?(:notes)
  end
end
