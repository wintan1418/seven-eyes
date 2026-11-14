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
    return redirect_to(read_path(ref: @query, t: params[:t].presence)) if open_reference?
    @scope = params[:in].to_s.presence || "all"
    @translation = Translation.available.find_by(code: params[:t].to_s.upcase.presence) ||
                   Translation.default
    @result = ScriptureSearch.call(@query, translation: @translation, scope: @scope)
  end

  private

  def open_reference?
    request.headers["Turbo-Frame"].blank? && @query.match?(/\d/) && ReferenceParser.call(@query).valid?
  end
end
