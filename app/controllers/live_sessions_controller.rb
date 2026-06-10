# Live "follow along": the pastor goes live from preach mode; congregants open
# /live/CODE on their phones and the passage follows the pulpit in real time.
#
# Operator endpoints (create/update/destroy) resolve the study through
# current_study, so they work for signed-in owners AND session-scoped guests.
# Follower endpoints (show/passage) are public — no account, no study access.
class LiveSessionsController < ApplicationController
  allow_unauthenticated_access

  # POST /studies/:study_id/live — go live (idempotent: reuses the active session)
  def create
    study = current_study(params[:study_id])
    live = study.live_session || study.live_sessions.create!
    apply_state(live)
    render json: live_payload(live)
  end

  # PATCH /studies/:study_id/live — push the pulpit's current state to the pews
  def update
    study = current_study(params[:study_id])
    live = study.live_session
    return head :not_found unless live
    return head :unprocessable_entity unless apply_state(live)

    LiveSessionChannel.broadcast_to(live, {
      type: "state",
      osis: live.osis, chapter: live.chapter,
      verse_start: live.verse_start, verse_end: live.verse_end,
      translation: live.translation_code,
      reference: live.reference_label
    })
    head :ok
  end

  # DELETE /studies/:study_id/live — end the live session
  def destroy
    study = current_study(params[:study_id])
    if (live = study.live_session)
      live.end!
      LiveSessionChannel.broadcast_to(live, { type: "ended" })
    end
    head :ok
  end

  # GET /live/:code — the follower page (ended sessions render a farewell state)
  def show
    @live = LiveSession.find_by(code: params[:code].to_s.upcase)
    render :not_found, status: :not_found unless @live
  end

  # GET /live/:code/passage — current passage HTML for the follower's container
  def passage
    live = LiveSession.find_active(params[:code])
    return head :not_found unless live
    render partial: "live_sessions/passage", locals: { live: live }, layout: false
  end

  private

  # Update the session from operator params. Reference parsing failures return
  # false (422) so a garbled push never blanks what the pews are reading.
  def apply_state(live)
    attrs = {}
    if params[:reference].present?
      parsed = ReferenceParser.call(params[:reference].to_s)
      return false unless parsed.valid?
      attrs[:osis] = parsed.osis
      attrs[:chapter] = parsed.chapter
    end
    if params[:translation_id].present?
      translation = Translation.find_by(id: params[:translation_id])
      attrs[:translation_code] = translation.code if translation
    end
    attrs[:translation_code] = Pane::DEFAULT_TRANSLATION if live.translation_code.blank? && attrs[:translation_code].blank?
    attrs[:verse_start] = params[:verse_start].to_i if params[:verse_start].present?
    attrs[:verse_end] = params[:verse_end].to_i if params[:verse_end].present?
    attrs.empty? ? true : live.update(attrs)
  end

  def live_payload(live)
    url = live_session_url(live.code)
    {
      code: live.code,
      url: url,
      qr_svg: RQRCode::QRCode.new(url).as_svg(module_size: 4, viewbox: true, use_path: true)
    }
  end
end
