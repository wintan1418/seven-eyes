# Live "follow along": the pastor goes live from preach mode; congregants open
# /live/CODE on their phones and the passage follows the pulpit in real time.
#
# Operator endpoints (create/update/destroy) resolve the study through
# current_study, so they work for signed-in owners AND session-scoped guests.
# Follower endpoints (show/passage/recap) are public — no account, no study access.
class LiveSessionsController < ApplicationController
  include LanHost
  allow_unauthenticated_access

  # POST /studies/:study_id/live — go live. Idempotent: concurrent clicks reuse
  # the one active session (LiveSession.start_for! locks the study row).
  # With resume=1 it only re-attaches a console to an already-active session
  # (e.g. after a Turbo navigation away and back) and never creates one.
  def create
    study = current_study(params[:study_id])
    if params[:resume].present?
      live = LiveSession.current_for(study)
      return head :not_found unless live
      return render json: live_payload(live)
    end

    live = LiveSession.start_for!(study)
    broadcast_state(live) if apply_state(live) == :applied
    render json: live_payload(live)
  end

  # PATCH /studies/:study_id/live — push the pulpit's current state to the pews
  def update
    study = current_study(params[:study_id])
    live = LiveSession.current_for(study)
    return head :not_found unless live

    case apply_state(live)
    when :applied
      broadcast_state(live)
      head :ok
    when :unchanged then head :ok
    when :stale then head :no_content # an older push arrived late — ignored
    else head :unprocessable_entity
    end
  end

  # DELETE /studies/:study_id/live — end the live session
  def destroy
    study = current_study(params[:study_id])
    if (live = LiveSession.current_for(study))
      live.end!
      LiveSessionChannel.broadcast_to(live, { type: "ended" })
    end
    head :ok
  end

  # GET /live/:code — the follower page (ended sessions render a farewell state)
  def show
    @live = LiveSession.find_by(code: LiveSession.normalize_code(params[:code]))
    return render :not_found, status: :not_found unless @live
    @live.expire! if @live.stale?
  end

  # GET /live/:code/passage — current passage HTML for the follower's container
  def passage
    live = LiveSession.find_active(params[:code])
    return head :not_found unless live
    render partial: "live_sessions/passage", locals: { live: live }, layout: false
  end

  # GET /live/:code/recap — "tonight's scriptures": every passage shown, in order.
  # Works for ended sessions too (the farewell overlay fetches it), for a week.
  def recap
    live = LiveSession.find_by(code: LiveSession.normalize_code(params[:code]))
    return head :not_found unless live&.recap_available?
    render partial: "live_sessions/recap", locals: { live: live }, layout: false
  end

  private

  def broadcast_state(live)
    LiveSessionChannel.broadcast_to(live, live.live_state)
  end

  # Update the session from operator params. Returns
  #   :applied   — state changed (broadcast it)
  #   :unchanged — nothing to apply (e.g. Go Live before any verse is shown)
  #   :stale     — the push carries an older sequence number than one already
  #                applied (requests can land out of order) — ignored
  #   false      — unreadable (422) so a garbled push never blanks the pews
  # The row lock makes the sequence check + write atomic across concurrent
  # PATCHes. A kind=slide push (song stanza / projected thought) swaps the pews
  # over to the slide; the next scripture push swaps them back.
  def apply_state(live)
    seq = params[:seq].presence&.to_i
    live.with_lock do
      next :stale if seq && seq <= live.state_seq
      attrs = params[:kind].to_s == "slide" ? slide_attrs : scripture_attrs(live)
      next false if attrs.nil?
      next :unchanged if attrs.empty?
      attrs[:state_seq] = seq if seq
      next false unless live.update(attrs)
      live.log_passage! unless live.slide?
      :applied
    end
  end

  def slide_attrs
    return nil if params[:slide_title].blank? && params[:slide_body].blank? && params[:slide_image_url].blank?
    { kind: "slide",
      slide_title: params[:slide_title].to_s.presence,
      slide_body: params[:slide_body].to_s.presence,
      slide_image_url: params[:slide_image_url].to_s.presence,
      slide_index: params[:slide_index].to_i }
  end

  # nil = unreadable reference; {} = nothing to change.
  def scripture_attrs(live)
    attrs = {}
    if params[:reference].present?
      parsed = ReferenceParser.call(params[:reference].to_s)
      return nil unless parsed.valid?
      attrs[:osis] = parsed.osis
      attrs[:chapter] = parsed.chapter
      # A new passage without a verse must not inherit the old chapter's range.
      if (parsed.osis != live.osis || parsed.chapter != live.chapter) && params[:verse_start].blank?
        attrs[:verse_start] = nil
        attrs[:verse_end] = nil
      end
      if live.translation_code.blank? && params[:translation_id].blank?
        attrs[:translation_code] = Pane::DEFAULT_TRANSLATION
      end
    end
    if params[:translation_id].present?
      translation = Translation.find_by(id: params[:translation_id])
      attrs[:translation_code] = translation.code if translation
    end
    attrs[:verse_start] = params[:verse_start].to_i if params[:verse_start].present?
    attrs[:verse_end] = params[:verse_end].to_i if params[:verse_end].present?
    return attrs if attrs.empty?

    attrs[:kind] = "scripture"
    attrs[:emphasis] = emphasis_param
    attrs
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
      operator_token: live.operator_token,
      url: url,
      qr_svg: RQRCode::QRCode.new(url).as_svg(module_size: 4, viewbox: true, use_path: true)
    }
  end
end
