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
    return redirect_to(read_path(ref: @query, t: params[:t].presence)) if request.format.html? && open_reference?
    @scope = params[:in].to_s.presence || "all"
    @translation = Translation.available.find_by(code: params[:t].to_s.upcase.presence) ||
                   Translation.available.find_by(id: params[:translation].presence) ||
                   Translation.default
    @result = ScriptureSearch.call(@query, translation: @translation, scope: @scope,
                                   limit: request.format.json? ? JSON_LIMIT : ScriptureSearch::LIMIT)
    respond_to do |format|
      format.html
      # The preach console's search-as-you-type when the Bible isn't on the device.
      format.json { render json: json_result }
    end
  end

  JSON_LIMIT = 30

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

  def open_reference?
    request.headers["Turbo-Frame"].blank? && @query.match?(/\d/) && ReferenceParser.call(@query).valid?
  end
end
