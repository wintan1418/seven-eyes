class PanesController < ApplicationController
  # Guests may navigate Scripture (reference/translation); only notes require an account.
  allow_unauthenticated_access only: %i[ update ]

  def update
    study = current_study(params[:study_id])
    @pane = study.panes.find(params[:id])

    # The projector / output window mirrors the operator's pane: render the
    # requested reference/translation without touching the saved study.
    if params[:mirror].present?
      @pane.assign_attributes(pane_params.except(:notes))
      return render partial: "panes/pane", locals: { pane: @pane }
    end

    # Writing notes is a "save" — it requires an account however it arrives
    # (the debounced autosave, a keepalive flush, or a full pane form).
    return head(:unauthorized) if writes_notes? && !authenticated?

    sync = nil
    if writes_notes?
      sync = NotesSync.call(pane: @pane, text: pane_params[:notes],
                            base_revision: params[:base_revision], edited_at: params[:edited_at])
      @pane.update(pane_params.except(:notes))
      response.headers["X-Notes-Revision"] = sync.revision.to_s
    else
      @pane.update(pane_params)
    end

    if sync && params[:autosave] && params.key?(:base_revision)
      # A replayed offline edit: say what the notes are now and whether the
      # offline text had to be added below a newer copy.
      render json: { notes: sync.notes, revision: sync.revision, conflict: sync.conflict? }
    elsif params[:autosave]
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
