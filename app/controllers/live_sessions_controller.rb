# Live "follow along": the pastor goes live from preach mode; congregants open
# /live/CODE on their phones and the passage follows the pulpit in real time.
#
# Operator endpoints (create/update/destroy) resolve the study through
# current_study, so they work for signed-in owners AND session-scoped guests.
# Follower endpoints (show/passage) are public — no account, no study access.
class LiveSessionsController < ApplicationController
  include LanHost
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

    LiveSessionChannel.broadcast_to(live, live.live_state)
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

  # GET /live/:code/recap — "tonight's scriptures": every passage shown, in order.
  # Works for ended sessions too (the farewell overlay fetches it).
  def recap
    live = LiveSession.find_by(code: params[:code].to_s.upcase)
    return head :not_found unless live
    render partial: "live_sessions/recap", locals: { live: live }, layout: false
  end

  private

  # Update the session from operator params. Reference parsing failures return
  # false (422) so a garbled push never blanks what the pews are reading.
  # A kind=slide push (song stanza / projected thought) swaps the pews over to
  # the slide; the next scripture push swaps them back.
  def apply_state(live)
    if params[:kind].to_s == "slide"
      return false if params[:slide_title].blank? && params[:slide_body].blank? && params[:slide_image_url].blank?
      return live.update(kind: "slide",
                         slide_title: params[:slide_title].to_s.presence,
                         slide_body: params[:slide_body].to_s.presence,
                         slide_image_url: params[:slide_image_url].to_s.presence,
                         slide_index: params[:slide_index].to_i)
    end

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
    return true if attrs.empty?

    attrs[:kind] = "scripture"
    attrs[:emphasis] = emphasis_param
    live.update(attrs).tap { |ok| live.log_passage! if ok }
  end

  # The minister's emphasised words, keyed by verse number → word indices.
  # Sanitised to integers since the keys are arbitrary (per-verse).
  def emphasis_param
    raw = params[:emphasis]
    raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
    return {} unless raw.is_a?(Hash)
    raw.each_with_object({}) do |(verse, words), out|
      out[verse.to_s] = Array(words).map(&:to_i)
    end
  end

  def live_payload(live)
    url = lan_visible_url(live_session_url(live.code))
    {
      code: live.code,
      url: url,
      qr_svg: RQRCode::QRCode.new(url).as_svg(module_size: 4, viewbox: true, use_path: true)
    }
  end
end
