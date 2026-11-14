# /search — Bible search as its own page (the apps' Search tab; also on the
# web). Ranked by ScriptureSearch: verses with the words side by side, then
# every word, then some; matched words marked. A result opens the reader at
# the whole chapter, scrolled to the verse (/read?ref=…). Offline, the
# search_page controller answers from a downloaded Bible.
class SearchController < ApplicationController
  allow_unauthenticated_access

  def show
    @query = params[:q].to_s.squish.first(200)
    @scope = params[:in].to_s.presence || "all"
    @translation = Translation.available.find_by(code: params[:t].to_s.upcase.presence) ||
                   Translation.default
    @result = ScriptureSearch.call(@query, translation: @translation, scope: @scope)
  end
end
