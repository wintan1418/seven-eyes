module ScriptureHelper
  ROMAN_PANE = %w[I II III IV].freeze

  # Pane index as a Roman numeral (I–IV) for the design's pane badges.
  def pane_numeral(position)
    ROMAN_PANE[position] || (position + 1).to_s
  end

  # Roman numeral for chapter headings ("Romans V"). Falls back to the integer
  # for very large numbers (e.g. Psalm 119) where Roman would be unwieldy.
  def to_roman(number)
    return number.to_s if number > 89

    map = { 100 => "C", 90 => "XC", 50 => "L", 40 => "XL", 10 => "X",
            9 => "IX", 5 => "V", 4 => "IV", 1 => "I" }
    result = +""
    remaining = number
    map.each do |value, letter|
      while remaining >= value
        result << letter
        remaining -= value
      end
    end
    result
  end

  # The design's grid class for a given pane count.
  def workspace_cols_class(pane_count)
    "cols-#{pane_count.clamp(1, 4)}"
  end

  # Heading like "Romans V" / "Psalm 119" from a parsed reference + book.
  def reference_title(book, chapter)
    "#{book.name} #{to_roman(chapter)}"
  end

  # Reference string for the chapter before or after the given one, wrapping at
  # book boundaries (Genesis 50:end ↔ Exodus 1) so prev/next reads like a Bible.
  # Returns nil if there is no neighbor (start of Genesis 1 / end of Revelation 22).
  def neighbor_reference(book, chapter, direction)
    pair =
      case direction
      when :next
        if chapter < book.chapter_count
          [ book, chapter + 1 ]
        else
          nxt = Book.where("position > ?", book.position).order(:position).first
          nxt && [ nxt, 1 ]
        end
      when :prev
        if chapter > 1
          [ book, chapter - 1 ]
        else
          prv = Book.where("position < ?", book.position).order(position: :desc).first
          prv && [ prv, prv.chapter_count ]
        end
      end
    pair && "#{pair[0].name} #{pair[1]}"
  end

  def translation_options(selected_id)
    options_from_collection_for_select(Translation.all, :id, :code, selected_id)
  end

  # Render one verse: a clickable superscript number (opens cross-references) plus
  # the verse text in a selectable container (used by the highlighter). The opening
  # drop cap is a pure-CSS ::first-letter treatment so character offsets stay exact.
  # Batch-load LexiconEntry rows for every Strong's number across the given
  # verses' tokens, returned as a strongs → entry hash. Used to enrich the
  # interlinear gloss without N+1 queries.
  def lexicon_lookup_for(verses)
    strongs = verses.flat_map { |v| Array(v.tokens).map { |t| t["s"] }.compact }.uniq
    return {} if strongs.empty?
    LexiconEntry.where(strongs: strongs).index_by(&:strongs)
  end

  def scripture_verse(verse, study:, book:, highlights: [], dropcap: false, lexicon: {})
    vnum = link_to(verse.verse_number,
                   cross_references_study_path(study, osis: book.osis_code,
                     chapter: verse.chapter, verse: verse.verse_number, translation: verse.translation.code),
                   class: "ps-vnum", title: "Cross-references",
                   data: { turbo_frame: "xref_drawer", action: "xref#open" })

    verse_data = { osis: book.osis_code, chapter: verse.chapter, verse_num: verse.verse_number }

    # Word-by-word Strong's tagging (KJV) takes precedence when present and the
    # verse isn't highlighted — highlight rendering and per-word spans don't mix.
    if verse.tokens.present? && highlights.blank?
      text_span = tag.span(strongs_tokens(verse.tokens, study, lexicon: lexicon),
                           class: "ps-verse-text", data: { verse_id: verse.id, offset_base: 0 })
      return tag.span(safe_join([ vnum, text_span, " " ]), class: "ps-verse", data: verse_data)
    end

    text = verse.text.to_s
    use_cap = dropcap && text.match?(/\A\p{Alpha}/)
    base = use_cap ? 1 : 0

    text_span = tag.span(highlight_text(text, highlights, base: base),
                         class: "ps-verse-text", data: { verse_id: verse.id, offset_base: base })

    parts = [ vnum ]
    parts << tag.span(text[0], class: "ps-dropcap", aria: { hidden: true }) if use_cap
    parts << text_span
    parts << " "
    tag.span(safe_join(parts), class: "ps-verse", data: verse_data)
  end

  # Render Strong's-tagged tokens: words with an "s" become clickable lexicon
  # links; everything else is plain text. Joined so the verse reads normally.
  # When +lexicon+ is supplied, attaches a data-gloss attribute carrying the
  # transliteration (or lemma fallback) plus the Strong's code — interlinear
  # mode renders it underneath each word via CSS.
  def strongs_tokens(tokens, study, lexicon: {})
    safe_join(tokens.map do |t|
      surface = t["w"].to_s
      if t["s"].present?
        entry = lexicon[t["s"]]
        readable = entry&.translit.presence || entry&.lemma.presence
        gloss = readable.present? ? "#{readable} · #{t["s"]}" : t["s"]
        link_to(surface, lexicon_study_path(study, strongs: t["s"]),
                class: "ps-word", title: gloss,
                data: { strongs: t["s"], gloss: gloss,
                        turbo_frame: "lexicon_drawer", action: "lexicon#open" })
      else
        surface
      end
    end)
  end

  # Render verse text from index +base+, wrapping each highlighted [char_start, char_end)
  # range (offsets index the full verse text) in an .hl-COLOR span. Overlaps are skipped.
  def highlight_text(text, highlights, base: 0)
    return html_escape(text[base..] || "") if highlights.blank?

    pieces = []
    cursor = base
    highlights.sort_by(&:char_start).each do |h|
      s = h.char_start.clamp(base, text.length)
      e = h.char_end.clamp(s, text.length)
      next if s < cursor
      pieces << html_escape(text[cursor...s]) if s > cursor
      classes = [ "hl-#{h.color}" ]
      classes << "has-note" if h.note.present?
      pieces << tag.span(html_escape(text[s...e]),
                         class: classes.join(" "),
                         data: { highlight_id: h.id, note: h.note.to_s })
      cursor = e
    end
    pieces << html_escape(text[cursor..]) if cursor < text.length
    safe_join(pieces)
  end
end
