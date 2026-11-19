# The work behind an AiRequest, split so the slow part runs in the job and the
# page renders in an ordinary request:
#
#   AiWork.run(request)            # in AiRequestJob: calls the AI service and
#                                  # returns a JSON-safe Hash
#   AiWork.rabbi_result(hash)      # in the poll request: the service Result
#   AiWork.illustration_result(h)  #   struct again, for the usual partial
#
# Only plain values are stored (no HTML): the partials render at poll time, in
# the viewer's own request, so CSRF tokens and helpers behave as before.
module AiWork
  module_function

  def run(request)
    params = request.params.to_h.with_indifferent_access
    case request.kind
    when "quick_find"         then quick_find(params)
    when "rabbi"              then rabbi(request, params)
    when "rabbi_illustration" then illustration(request, params)
    else raise ArgumentError, "unknown AI request kind #{request.kind}"
    end
  end

  def verses_for(ids)
    ids = Array(ids).map(&:to_i).reject(&:zero?).uniq
    return [] if ids.empty?
    Verse.includes(:book, :translation).where(id: ids).sort_by { |v| [ v.chapter, v.verse_number ] }
  end

  # The JSON the Go box has always rendered.
  def quick_find(params)
    result = PulpitSearch.call(params[:q])
    return { "ok" => false, "error" => result.error.to_s } unless result.ok?

    {
      "ok" => true,
      # Model-written prose is reduced to plain text (no injected markup/links).
      "topic" => PlainText.call(result.topic, limit: 120),
      "summary" => PlainText.call(result.summary),
      "suggestions" => result.suggestions.map do |s|
        book = Bible::Canon.find(s.osis)
        {
          "reference" => s.reference,
          "chapter_reference" => "#{book&.name || s.osis} #{s.chapter}",
          "verse_start" => s.verse_start,
          "preview" => s.preview.to_s.truncate(140)
        }
      end
    }
  end

  def rabbi(request, params)
    verses = verses_for(params[:verse_ids])
    result = RabbiExposition.call(verse: verses.first, verses:, selection: params[:q], study: request.study)
    {
      "ok" => result.ok?, "error" => result.error&.to_s, "origin" => result.origin,
      "selection" => result.selection, "provider" => result.provider&.to_s,
      "exposition" => result.exposition&.to_h&.stringify_keys,
      "cross_references" => Array(result.cross_references).map { |c| c.to_h.stringify_keys }
    }
  end

  def rabbi_result(hash)
    h = hash.to_h
    ex = h["exposition"]
    RabbiExposition::Result.new(
      ok: h["ok"], error: h["error"]&.to_sym, origin: h["origin"], selection: h["selection"],
      provider: h["provider"]&.to_sym,
      exposition: ex && RabbiExposition::Exposition.new(**ex.symbolize_keys.slice(*RabbiExposition::Exposition.members)),
      cross_references: Array(h["cross_references"]).map do |c|
        RabbiExposition::CrossRef.new(**c.symbolize_keys.slice(*RabbiExposition::CrossRef.members))
      end
    )
  end

  # The illustration slot was reserved by the web request; a failed painting
  # hands it back here, exactly as the synchronous action did.
  def illustration(request, params)
    verses = verses_for(params[:verse_ids])
    result = RabbiIllustration.call(verse: verses.first, verses:, selection: params[:q],
                                    study: request.study, style: params[:style])
    request.release_quota! unless result.ok?
    {
      "ok" => result.ok?, "error" => result.error&.to_s, "image" => result.image,
      "caption" => result.caption, "origin" => result.origin, "provider" => result.provider&.to_s,
      "style" => result.style,
      "annotations" => Array(result.annotations).map { |a| a.to_h.stringify_keys }
    }
  end

  def illustration_result(hash)
    h = hash.to_h
    RabbiIllustration::Result.new(
      ok: h["ok"], error: h["error"]&.to_sym, image: h["image"], caption: h["caption"],
      origin: h["origin"], provider: h["provider"]&.to_sym, style: h["style"],
      annotations: Array(h["annotations"]).map do |a|
        RabbiIllustration::Annotation.new(**a.symbolize_keys.slice(*RabbiIllustration::Annotation.members))
      end
    )
  end
end
