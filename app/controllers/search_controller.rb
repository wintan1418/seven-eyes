# /search — Bible search as its own page (the apps' Search tab; also on the
# web). Ranked by ScriptureSearch: verses with the words side by side, then
# every word, then some; matched words marked. A result opens the reader at
# the whole chapter, scrolled to the verse (/read?ref=…). Offline, the
# search_page controller answers from a downloaded Bible.
class SearchController < ApplicationController
  allow_unauthenticated_access

  def show
    @query = params[:q].to_s.squish.first(200)
    # "John 3:16" or "ps 23" (a reference, with a number) opens the reader
    # there — the home page has one box for both. Not inside the results frame.
    # The Auto | Reference | Words switch (lib/scripture_mode.js): Reference
    # opens the passage or says it isn't one; Words never redirects.
    @mode = MODES.include?(params[:mode]) ? params[:mode] : "auto"
    if @mode == "reference" && request.format.html?
      parsed = ReferenceParser.call(tidy_reference(@query))
      return redirect_to(read_path(ref: parsed.label, t: params[:t].presence)) if parsed.valid?
      @not_reference = @query.present?
    end
    return redirect_to(read_path(ref: @query, t: params[:t].presence)) if @mode == "auto" && request.format.html? && open_reference?
    @scope = params[:in].to_s.presence || "all"
    @translation = Translation.available.find_by(code: params[:t].to_s.upcase.presence) ||
                   Translation.available.find_by(id: params[:translation].presence) ||
                   Translation.default
    @result = ScriptureSearch.call(@not_reference ? "" : @query, translation: @translation, scope: @scope,
                                   limit: request.format.json? ? JSON_LIMIT : ScriptureSearch::LIMIT)
    respond_to do |format|
      format.html
      # The preach console's search-as-you-type when the Bible isn't on the device.
      format.json { render json: json_result }
    end
  end

  JSON_LIMIT = 30
  MODES = %w[ auto reference words ].freeze

  private

  def json_result
    {
      ok: true, query: @query, translation: @translation&.code,
      hits: @result.hits.map do |hit|
        v = hit.verse
        { reference: hit.reference, osis: v.book.osis_code, chapter: v.chapter, num: v.verse_number,
          text: v.text, tier: hit.tier }
      end
    }
  end

  # A letter O typed for a zero next to a number ("john 1O:30") — the same
  # forgiveness as tidyReference in lib/scripture_mode.js.
  def tidy_reference(raw)
    s = raw.to_s.squish
    3.times { s = s.gsub(/(\d)[oO]/, '\10') }
    s.gsub(/(^|[\s:.,-])[oO](?=\d)/, '\10')
  end

  def open_reference?
    request.headers["Turbo-Frame"].blank? && @query.match?(/\d/) && ReferenceParser.call(@query).valid?
  end
end
