# Finds places in this user's pane notes that wiki-link (via [[ref]]) to a
# given verse. Pre-filters with an ILIKE for "[[" to skip notes that can't
# possibly contain a wiki-link, then validates each match with ReferenceParser
# so equivalences like "Jn 3:16" / "John 3:16" all resolve to the same target.
class BacklinksLookup
  Match = Struct.new(:pane, :study, :reference, :snippet, keyword_init: true)

  PATTERN = /\[\[([^\]\n]+)\]\]/

  def self.for(user:, book:, chapter:, verse: nil)
    return [] unless user

    panes = Pane.joins(:study)
                .where(studies: { user_id: user.id })
                .where.not(notes: nil)
                .where("notes ILIKE ?", "%[[%")
                .includes(:study)

    panes.each_with_object([]) do |pane, matches|
      next if pane.notes.blank?
      pane.notes.scan(PATTERN).each do |(ref_text)|
        next unless matches_verse?(ref_text, book, chapter, verse)
        matches << Match.new(
          pane: pane,
          study: pane.study,
          reference: pane.reference.presence || "—",
          snippet: extract_snippet(pane.notes, ref_text)
        )
        break # one match per pane is enough — surface the pane, not every link in it
      end
    end
  end

  def self.matches_verse?(ref_text, book, chapter, verse)
    parsed = ReferenceParser.call(ref_text)
    return false unless parsed.valid?
    return false unless parsed.osis == book.osis_code && parsed.chapter == chapter
    return true if verse.nil? || parsed.verse_start.nil?

    last = parsed.verse_end || parsed.verse_start
    (parsed.verse_start..last).cover?(verse)
  end

  def self.extract_snippet(notes, ref_text)
    needle = "[[#{ref_text}]]"
    idx = notes.index(needle)
    return notes.to_s.first(140) unless idx
    from = [idx - 50, 0].max
    to = [idx + needle.length + 50, notes.length].min
    snippet = notes[from...to]
    snippet = "…#{snippet}" if from > 0
    snippet = "#{snippet}…" if to < notes.length
    snippet
  end
end
