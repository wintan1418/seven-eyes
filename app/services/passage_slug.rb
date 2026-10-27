# Reversible, human-readable URL slugs for a passage, used by the public
# share pages (/p/:slug).
#
#   PassageSlug.slug_for(osis: "1Cor", chapter: 13, verse_start: 1, verse_end: 13)
#   => "1-corinthians-13-1-13"
#   PassageSlug.reference_for("1-corinthians-13-1-13") => "1 corinthians 13:1-13"
#
# Spans beyond one chapter use "-to-": "matthew-5-to-7" (Matthew 5-7) and
# "john-3-16-to-4-2" (John 3:16-4:2); "john-3-16-ff" is John 3:16ff.
#
# The book name is parameterized; the chapter and (optional) verse range follow
# as trailing numeric segments. Reversal works because no book name *ends* in a
# digit, so the trailing run of pure-number tokens is unambiguously the location.
module PassageSlug
  module_function

  def slug_for(osis:, chapter:, verse_start: nil, verse_end: nil, chapter_end: nil, open_ended: false)
    entry = Bible::Canon.find(osis)
    name  = entry ? entry.name : osis.to_s
    parts = [ name.parameterize, chapter ]
    multi = chapter_end && chapter_end > chapter
    if verse_start
      parts << verse_start
      if open_ended
        parts << "ff"
      elsif multi
        parts.push("to", chapter_end, verse_end)
      elsif verse_end && verse_end != verse_start
        parts << verse_end
      end
    elsif multi
      parts.push("to", chapter_end)
    end
    parts.compact.join("-")
  end

  def slug_from_result(result)
    slug_for(osis: result.osis, chapter: result.chapter,
             verse_start: result.verse_start, verse_end: result.verse_end,
             chapter_end: result.chapter_end, open_ended: result.open_ended?)
  end

  # Turn a slug back into a reference string ReferenceParser can read, or nil.
  def reference_for(slug)
    s = slug.to_s.downcase
    ff = s.end_with?("-ff") ? "ff" : ""
    s = s.delete_suffix("-ff")
    head, tail = s.split("-to-", 2)

    base = base_reference(head)
    return nil unless base

    if tail
      return nil unless tail.match?(/\A\d+(?:-\d+)?\z/)
      chapter_end, verse_end = tail.split("-")
      base += verse_end ? "-#{chapter_end}:#{verse_end}" : "-#{chapter_end}"
    end
    base + ff
  end

  def base_reference(slug)
    tokens = slug.to_s.split("-")
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
