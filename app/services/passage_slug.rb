# Reversible, human-readable URL slugs for a passage, used by the public
# share pages (/p/:slug).
#
#   PassageSlug.slug_for(osis: "1Cor", chapter: 13, verse_start: 1, verse_end: 13)
#   => "1-corinthians-13-1-13"
#   PassageSlug.reference_for("1-corinthians-13-1-13") => "1 corinthians 13:1-13"
#
# The book name is parameterized; the chapter and (optional) verse range follow
# as trailing numeric segments. Reversal works because no book name *ends* in a
# digit, so the trailing run of pure-number tokens is unambiguously the location.
module PassageSlug
  module_function

  def slug_for(osis:, chapter:, verse_start: nil, verse_end: nil)
    entry = Bible::Canon.find(osis)
    name  = entry ? entry.name : osis.to_s
    parts = [ name.parameterize, chapter ]
    if verse_start
      parts << verse_start
      parts << verse_end if verse_end && verse_end != verse_start
    end
    parts.join("-")
  end

  def slug_from_result(result)
    slug_for(osis: result.osis, chapter: result.chapter,
             verse_start: result.verse_start, verse_end: result.verse_end)
  end

  # Turn a slug back into a reference string ReferenceParser can read, or nil.
  def reference_for(slug)
    tokens = slug.to_s.downcase.split("-")
    nums = []
    nums.unshift(tokens.pop) while tokens.any? && tokens.last.match?(/\A\d+\z/)
    return nil if tokens.empty? || nums.empty?

    book = tokens.join(" ")
    case nums.size
    when 1 then "#{book} #{nums[0]}"
    when 2 then "#{book} #{nums[0]}:#{nums[1]}"
    else        "#{book} #{nums[0]}:#{nums[1]}-#{nums[2]}"
    end
  end
end
