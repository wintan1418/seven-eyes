# Offline reading: the Downloads page, the per-translation Bible bundles the
# device stores in IndexedDB, and the signed-in reader's highlights (so a
# chapter rendered offline still shows them). See OfflineBundle and
# app/javascript/lib/offline/.
class OfflineController < ApplicationController
  allow_unauthenticated_access only: %i[ show manifest bible highlights ]

  # Icons the offline pane renderer draws (same markup as ReaderHelper#icon).
  RENDER_ICONS = %i[ chevron_down chevron_left chevron_right listen memorize notes x commentary image prayer book help ].freeze

  def show
  end

  # GET /offline/bibles — what can be downloaded, plus the book list and
  # reference aliases the device needs to read references without the server.
  def manifest
    # Small, and must never be stale (its versions and ids drive downloads).
    response.headers["Cache-Control"] = "no-cache"
    render json: {
      format: OfflineBundle::FORMAT,
      default_code: Translation.default&.code,
      translations: OfflineBundle.manifest.map { |t| t.merge(url: offline_bible_path(t[:code], v: t[:version])) },
      books: Book.all.map { |b| { osis: b.osis_code, name: b.name, chapters: b.chapter_count, position: b.position } },
      canon: Bible::Canon.all.map { |b| { osis: b.osis, name: b.name, testament: b.testament, chapters: b.chapter_count, aliases: b.aliases } },
      icons: RENDER_ICONS.index_with { |name| helpers.icon(name).to_s }
    }
  end

  # GET /offline/bibles/:code — one whole translation, gzipped. Versioned URLs
  # (?v=) are immutable and cached for a year; ETags answer re-checks.
  def bible
    translation = Translation.available.find_by("LOWER(translations.code) = ?", params[:code].to_s.downcase)
    return head(:not_found) unless translation

    bundle = OfflineBundle.new(translation)
    if params[:v].present? && params[:v] == bundle.version
      expires_in 1.year, public: true, immutable: true
    else
      expires_in 5.minutes, public: true
    end
    return unless stale?(etag: bundle.version, public: true)

    response.headers["Vary"] = "Accept-Encoding"
    if request.headers["Accept-Encoding"].to_s.include?("gzip")
      response.headers["Content-Encoding"] = "gzip"
      send_data bundle.gzip, type: :json, disposition: :inline
    else
      send_data bundle.json, type: :json, disposition: :inline
    end
  end

  # GET /offline/highlights — the reader's own highlights, for offline display.
  def highlights
    return head(:unauthorized) unless authenticated?

    response.headers["Cache-Control"] = "private, no-store"
    render json: {
      highlights: current_user.highlights.pluck(:id, :verse_id, :char_start, :char_end, :color, :note).map do |id, verse_id, s, e, color, note|
        { id:, verse_id:, char_start: s, char_end: e, color:, note: note.to_s }
      end
    }
  end
end
