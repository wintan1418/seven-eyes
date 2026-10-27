# Finds verses a translation leaves out of a passage, and another translation
# that carries them, so a pane can say "Matthew 18:11 isn't in the BSB (it's in
# the KJV)" instead of rendering a gap — or nothing at all.
#
#   PassageGaps.within(verses, parsed)                                      => [[18, 11]]
#   PassageGaps.alternative_for(book:, translation:, locations: [[18, 11]]) => KJV
#   PassageGaps.alternative_for(book:, translation:, chapter: 3)            => a translation with that chapter
module PassageGaps
  module_function

  # [chapter, verse] pairs absent from +verses+ but inside the span they cover:
  # from the requested first verse (or 1) up to the last verse returned in each
  # chapter. Gaps past the last verse can't be told apart from a short chapter,
  # so they are not reported.
  def within(verses, parsed)
    verses.group_by(&:chapter).flat_map do |chapter, rows|
      present = rows.map(&:verse_number)
      lower = chapter == parsed.chapter && parsed.verse_start ? parsed.verse_start : 1
      ((lower..present.max).to_a - present).map { |v| [ chapter, v ] }
    end
  end

  # An offered translation (KJV first) other than +translation+ that has every
  # one of +locations+, or — with +chapter+ — any text for that chapter.
  # Translations with a different versification (DRA) are never suggested.
  def alternative_for(book:, translation:, locations: nil, chapter: nil)
    candidates = Translation.available.where.not(id: translation&.id)
                            .where.not(code: Translation::VULGATE_NUMBERING).to_a
    return nil if candidates.empty?

    scope = Verse.where(book:, translation_id: candidates.map(&:id))
    ids =
      if chapter
        scope.where(chapter:).distinct.pluck(:translation_id)
      else
        locations = Array(locations).uniq
        return nil if locations.empty?
        scope.where([ :chapter, :verse_number ] => locations)
             .group(:translation_id).having("COUNT(*) = ?", locations.size).count.keys
      end
    preferred(candidates.select { |t| ids.include?(t.id) })
  end

  def preferred(translations)
    translations.min_by { |t| [ t.code == Translation::DEFAULT_CODE ? 0 : 1, t.id ] }
  end
end
