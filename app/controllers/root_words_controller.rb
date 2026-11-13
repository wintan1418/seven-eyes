# Root words for preach mode (see RootWords):
#   GET  /root_words/:osis/:chapter/:verse  — a verse's KJV Strong's words + entries (JSON, public)
#   GET  /root_words/pack                   — the offline word pack (gzipped JSON, versioned)
#   POST /root_words/explain                — "Ask Rabbi": a 1–2 sentence explanation (AI; account)
class RootWordsController < ApplicationController
  allow_unauthenticated_access only: %i[ verse pack pack_info explain ]

  rate_limit to: 20, within: 1.minute, only: :explain, name: "ai-burst",
             by: -> { Current.user&.id || request.remote_ip },
             with: -> { render json: { ok: false, error: "rate_limited" }, status: :too_many_requests }

  def verse
    payload = RootWords.verse(osis: params[:osis].to_s, chapter: params[:chapter], verse: params[:verse])
    return render(json: { ok: false, error: "not_found" }, status: :not_found) unless payload

    expires_in 1.hour, public: true
    render json: payload
  end

  def pack
    pack = RootWordPack.new
    return head(:not_found) unless pack.available?

    if params[:v].present? && params[:v] == pack.version
      expires_in 1.year, public: true, immutable: true
    else
      expires_in 5.minutes, public: true
    end
    return unless stale?(etag: pack.version, public: true)

    response.headers["Vary"] = "Accept-Encoding"
    if request.headers["Accept-Encoding"].to_s.include?("gzip")
      response.headers["Content-Encoding"] = "gzip"
      send_data pack.gzip, type: :json, disposition: :inline
    else
      send_data pack.json, type: :json, disposition: :inline
    end
  end

  # GET /root_words/pack/info — the pack's version and size, before downloading it.
  def pack_info
    pack = RootWordPack.new
    return head(:not_found) unless pack.available?

    response.headers["Cache-Control"] = "no-cache"
    render json: pack.summary.merge(url: root_words_pack_path(v: pack.version))
  end

  def explain
    return render(json: { ok: false, error: "auth_required" }, status: :unauthorized) unless authenticated?
    unless AiBudget.charge_user(current_user.id)
      return render(json: { ok: false, error: "daily_limit" }, status: :too_many_requests)
    end

    entry = LexiconEntry.lookup(params[:strongs])
    book = Book.find_by_osis(params[:osis].to_s)
    verse = book && RootWords.kjv&.verses&.find_by(book:, chapter: params[:chapter].to_i, verse_number: params[:verse].to_i)
    result = RootWordExplainer.call(entry:, verse:, word: params[:word])
    render json: { ok: result.ok?, text: result.text, error: result.error }
  end
end
