module ScriptureHelper
  ROMAN_PANE = %w[I II III IV].freeze

  NOTE_LINK_RE = /\[\[([^\]\n]+)\]\]/
  NOTE_LINK_PLACEHOLDER = "\u{E010}NOTELINK_%d\u{E011}".freeze

  # Render note text with `[[John 3:16]]` style wiki-links resolved against
  # ReferenceParser + Book and turned into clickable links into the xref drawer.
  # Falls through `simple_format` for paragraph/<br> handling so multi-line
  # notes still read like prose.
  #
  # Notes are untrusted user text and appear on public share pages: the text is
  # HTML-escaped BEFORE simple_format (which runs unsanitised only so the
  # placeholders survive), and only links we generate are spliced back in.
  def render_notes(text, study:)
    return "".html_safe if text.blank?
    links = []
    with_placeholders = text.to_str.gsub(NOTE_LINK_RE) do
      links << note_link_to(::Regexp.last_match(1), study)
      NOTE_LINK_PLACEHOLDER % (links.size - 1)
    end
    escaped = ERB::Util.html_escape(with_placeholders).to_str
    out = simple_format(escaped, {}, sanitize: false).to_s
    links.each_with_index { |link, i| out = out.sub(NOTE_LINK_PLACEHOLDER % i, link.to_s) }
    out.html_safe
  end

  def note_link_to(ref_text, study)
    parsed = ReferenceParser.call(ref_text)
    if parsed.valid? && (book = Book.find_by_osis(parsed.osis))
      translation_code = (study.panes.find_by(translation_id: nil).nil? &&
                          study.panes.first&.effective_translation&.code) || "KJV"
      link_to("[[#{parsed.label}]]",
              cross_references_study_path(study,
                osis: book.osis_code, chapter: parsed.chapter,
                verse: parsed.verse_start || 1, translation: translation_code),
              class: "ps-note-link",
              data: { turbo_frame: "xref_drawer", action: "xref#open" })
    else
      ERB::Util.html_escape("[[#{ref_text}]]")
    end
  end

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

  # Heading like "Romans V" / "Psalm 119" from a parsed reference + book;
  # "Matthew V–VII" when the pane spans several chapters.
  def reference_title(book, chapter, last_chapter = nil)
    title = "#{book.name} #{to_roman(chapter)}"
    title += "–#{to_roman(last_chapter)}" if last_chapter && last_chapter > chapter
    title
  end

  # Reference string for the chapter before or after the given one, wrapping at
  # book boundaries (Genesis 50:end ↔ Exodus 1) so prev/next reads like a Bible.
  # Returns nil if there is no neighbor (start of Genesis 1 / end of Revelation 22).
  # For a multi-chapter pane pass its first chapter for :prev, last for :next.
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

  # One-click fix inside a pane: re-render this pane's frame with another
  # translation and/or reference ("Show in KJV", "Show John 3:21").
  def pane_switch_button(pane, label, translation: nil, reference: nil)
    attrs = { reference: reference || pane.reference }
    attrs[:translation_id] = translation.id if translation
    button_to label, study_pane_path(pane.study, pane), method: :patch,
              params: { pane: attrs },
              class: "ps-pane-fix mt-2 cursor-pointer border border-gold px-3 py-1 font-display text-[10px] " \
                     "uppercase tracking-[0.18em] text-rubric hover:bg-vellum-2",
              form: { data: { turbo_frame: pane.frame_id }, class: "inline" }
  end

  # "Matthew 18:11" / "verses 11 and 12" — the [chapter, verse] pairs a pane is missing.
  def missing_verses_label(book, locations)
    return "#{book.name} #{locations.first[0]}:#{locations.first[1]}" if locations.size == 1
    by_chapter = locations.group_by(&:first)
    by_chapter.map { |ch, pairs| "#{book.name} #{ch}:#{pairs.map(&:last).to_sentence}" }.join("; ")
  end

  # Only translations readers may use (complete, not licence-restricted).
  def translation_options(selected_id)
    options_for_select(Translation.available.map { |t| [ t.code, t.id, { title: t.display_name } ] }, selected_id)
  end

  # Batch-load LexiconEntry rows for every Strong's number across the given
  # verses' tokens, returned as a strongs → entry hash. Used to enrich the
  # interlinear gloss without N+1 queries.
  def lexicon_lookup_for(verses)
    strongs = verses.flat_map { |v| Array(v.tokens).map { |t| t["s"] }.compact }.uniq
    return {} if strongs.empty?
    LexiconEntry.where(strongs: strongs).index_by(&:strongs)
  end

  # Render one verse: a clickable superscript number (opens cross-references) plus
  # the verse text in a selectable container (used by the highlighter). The opening
  # drop cap is a pure-CSS-styled first letter outside the text span, with
  # data-offset-base telling the highlighter where the span's text starts.
  #
  # Strong's-tagged words (KJV) and highlights render together over one text:
  # the segments always concatenate to exactly verse.text, so the character
  # offsets the highlighter records line up however a verse is drawn.
  # Pass +translation+ to avoid loading verse.translation per verse.
  #
  # link_numbers: false renders a read-only verse (public share pages): the
  # number is a plain span and Strong's words carry no lexicon link/action.
  def scripture_verse(verse, study:, book:, highlights: [], dropcap: false, lexicon: {}, translation: nil,
                      link_numbers: true)
    vnum =
      if link_numbers
        translation_code = (translation || verse.translation).code
        link_to(verse.verse_number,
                cross_references_study_path(study, osis: book.osis_code,
                  chapter: verse.chapter, verse: verse.verse_number, translation: translation_code),
                class: "ps-vnum", title: "Cross-references",
                data: { turbo_frame: "xref_drawer", action: "xref#open" })
      else
        tag.span(verse.verse_number, class: "ps-vnum")
      end

    verse_data = { osis: book.osis_code, chapter: verse.chapter, verse_num: verse.verse_number }

    text = verse.text.to_s
    use_cap = dropcap && text.match?(/\A\p{Alpha}/)
    base = use_cap ? 1 : 0

    text_span = tag.span(render_segments(verse_segments(verse), highlights, study:, lexicon:, base:,
                                         interactive: link_numbers),
                         class: "ps-verse-text", data: { verse_id: verse.id, offset_base: base })

    parts = [ vnum ]
    parts << tag.span(text[0], class: "ps-dropcap", aria: { hidden: true }) if use_cap
    parts << text_span
    parts << " "
    tag.span(safe_join(parts), class: "ps-verse", data: verse_data)
  end

  # The verse as ordered segments { text:, strongs: } whose texts concatenate to
  # exactly verse.text. Strong's tokens are laid over the verse text letter by
  # letter — their whitespace and typography may differ (Verse.fold_char) — and
  # each character of verse.text is assigned to the token it came from. If the
  # tokens don't spell the same words, the verse renders as plain text rather
  # than as something other than its stored text.
  def verse_segments(verse)
    text = verse.text.to_s
    plain = [ { text: text, strongs: nil } ]
    tokens = Array(verse.tokens)
    return plain if tokens.empty?

    # Every non-space token character, folded, tagged with its token index.
    stream = tokens.each_with_index.flat_map do |t, i|
      t["w"].to_s.gsub(/\s+/, "").each_char.flat_map { |c| Verse.fold_char(c).chars.map { |f| [ f, i ] } }
    end

    owners = Array.new(text.length) # token index owning each text character
    pos = 0
    text.each_char.with_index do |c, idx|
      next if c.match?(/\s/)
      folded = Verse.fold_char(c)
      slice = stream[pos, folded.length]
      return plain unless slice&.size == folded.length && slice.map(&:first).join == folded
      owners[idx] = slice.first.last
      pos += folded.length
    end
    return plain unless pos == stream.size

    # Whitespace inside one token ("into the land") stays with it; whitespace
    # between tokens stays plain, so a Strong's span never starts or ends with
    # a space (no stray underline on hover, offsets match the visible word).
    prev_owner = nil
    gaps = []
    text.each_char.with_index do |c, i|
      if c.match?(/\s/)
        gaps << i
      else
        gaps.each { |g| owners[g] = owners[i] } if prev_owner && prev_owner == owners[i]
        gaps.clear
        prev_owner = owners[i]
      end
    end

    segments = []
    text.each_char.with_index do |c, i|
      if segments.last && segments.last[:owner] == owners[i]
        segments.last[:text] << c
      else
        segments << { text: +c, owner: owners[i] }
      end
    end
    segments.map { |s| { text: s[:text], strongs: s[:owner] && tokens[s[:owner]]["s"].presence } }
  end

  # Render segments from character +base+, wrapping highlighted ranges in
  # .hl-COLOR spans and Strong's words in .ps-word spans. A word cut by a
  # highlight edge becomes two .ps-word spans with the same Strong's number.
  def render_segments(segments, highlights, study:, lexicon: {}, base: 0, interactive: true)
    pieces = []
    pos = 0
    segments.each do |seg|
      seg_start = pos
      pos += seg[:text].length
      next if pos <= base
      from = [ base, seg_start ].max
      pieces << { from:, to: pos, text: seg[:text][(from - seg_start)..], strongs: seg[:strongs] }
    end

    out = highlight_runs(highlights, base, pos).map do |run|
      inner = pieces.filter_map do |p|
        s = [ p[:from], run[:from] ].max
        e = [ p[:to], run[:to] ].min
        next if e <= s
        piece_text = p[:text][(s - p[:from])...(e - p[:from])]
        p[:strongs] ? strongs_word(piece_text, p[:strongs], study, lexicon, interactive:) : piece_text
      end
      h = run[:highlight]
      next safe_join(inner) unless h
      classes = [ "hl-#{h.color}" ]
      classes << "has-note" if h.note.present?
      tag.span(safe_join(inner), class: classes.join(" "), data: { highlight_id: h.id, note: h.note.to_s })
    end
    safe_join(out)
  end

  # Partition [from, to) into runs, each covered by at most one highlight.
  # Overlaps are resolved rather than dropped: the innermost (shortest)
  # highlight wins where they overlap, ties going to the newest, so every
  # highlight keeps a visible, clickable stretch unless another covers it exactly.
  def highlight_runs(highlights, from, to)
    spans = Array(highlights).filter_map do |h|
      s = h.char_start.to_i.clamp(from, to)
      e = h.char_end.to_i.clamp(s, to)
      [ s, e, h ] if e > s
    end
    cuts = ([ from, to ] + spans.flat_map { |s, e, _| [ s, e ] }).uniq.sort
    runs = []
    cuts.each_cons(2) do |a, b|
      winner = spans.select { |s, e, _| s <= a && e >= b }
                    .min_by { |s, e, h| [ e - s, -h.id.to_i ] }&.last
      if runs.last && runs.last[:highlight].equal?(winner)
        runs.last[:to] = b
      else
        runs << { from: a, to: b, highlight: winner }
      end
    end
    runs
  end

  # Render Strong's-tagged tokens: words with an "s" become clickable lexicon
  # words; everything else is plain text. Joined so the verse reads normally.
  def strongs_tokens(tokens, study, lexicon: {})
    safe_join(tokens.map do |t|
      t["s"].present? ? strongs_word(t["w"].to_s, t["s"], study, lexicon) : t["w"].to_s
    end)
  end

  # One Strong's word. When +lexicon+ is supplied, attaches a data-gloss
  # attribute carrying the transliteration (or lemma fallback) plus the Strong's
  # code — interlinear mode renders it underneath each word via CSS.
  #
  # Deliberately NOT a real <a> link: mobile browsers treat a long-press on an
  # anchor as "open the link menu", which blocks selecting Scripture text for
  # highlights / the Rabbi. The lexicon controller loads the drawer frame from
  # data-href instead.
  def strongs_word(surface, strongs, study, lexicon, interactive: true)
    entry = lexicon[strongs]
    readable = entry&.translit.presence || entry&.lemma.presence
    gloss = readable.present? ? "#{readable} · #{strongs}" : strongs
    return tag.span(surface, class: "ps-word", title: gloss, data: { strongs:, gloss: }) unless interactive

    tag.span(surface,
             class: "ps-word", title: gloss, role: "link", tabindex: "0",
             data: { strongs: strongs, gloss: gloss,
                     href: lexicon_study_path(study, strongs: strongs),
                     action: "click->lexicon#open keydown.enter->lexicon#open" })
  end

  # Render plain verse text from index +base+, wrapping each highlighted
  # [char_start, char_end) range (offsets index the full verse text) in an
  # .hl-COLOR span. Overlapping highlights are clipped, never dropped.
  def highlight_text(text, highlights, base: 0)
    render_segments([ { text: text.to_s, strongs: nil } ], highlights, study: nil, base: base)
  end
end
