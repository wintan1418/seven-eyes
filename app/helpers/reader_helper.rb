# View helpers for the modern reader (app bar, pickers, chapter heading).
module ReaderHelper
  # A handful of icons drawn after Lucide (https://lucide.dev, ISC licence):
  # 24×24, 2px round strokes, currentColor. Inline so they theme with the text.
  ICONS = {
    menu: '<path d="M4 6h16M4 12h16M4 18h16"/>',
    search: '<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>',
    chevron_down: '<path d="m6 9 6 6 6-6"/>',
    chevron_left: '<path d="m15 18-6-6 6-6"/>',
    chevron_right: '<path d="m9 18 6-6-6-6"/>',
    x: '<path d="M18 6 6 18M6 6l12 12"/>',
    type: '<path d="M4 7V5h16v2M9 19h6M12 5v14"/>',
    columns: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M12 4v16"/>',
    presentation: '<path d="M2 4h20M3 4v11a1 1 0 0 0 1 1h16a1 1 0 0 0 1-1V4M12 16v4M8 22l4-2 4 2"/>',
    book: '<path d="M2 4h6a4 4 0 0 1 4 4v13a3 3 0 0 0-3-3H2zM22 4h-6a4 4 0 0 0-4 4v13a3 3 0 0 1 3-3h7z"/>',
    notes: '<path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z"/>',
    calendar: '<rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18M9 16l2 2 4-4"/>',
    more: '<circle cx="12" cy="12" r="1.2"/><circle cx="19" cy="12" r="1.2"/><circle cx="5" cy="12" r="1.2"/>',
    sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
    moon: '<path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"/>',
    share: '<path d="M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8M16 6l-4-4-4 4M12 2v13"/>',
    copy: '<rect x="8" y="8" width="14" height="14" rx="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/>',
    link: '<path d="M10 13a5 5 0 0 0 7.5.5l3-3a5 5 0 0 0-7-7l-1.7 1.7"/><path d="M14 11a5 5 0 0 0-7.5-.5l-3 3a5 5 0 0 0 7 7l1.7-1.7"/>',
    queue: '<path d="M21 15V6M18.5 18a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5ZM12 12H3M16 6H3M12 18H3"/>',
    listen: '<path d="M3 14h3a2 2 0 0 1 2 2v3a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-7a9 9 0 0 1 18 0v7a2 2 0 0 1-2 2h-1a2 2 0 0 1-2-2v-3a2 2 0 0 1 2-2h3"/>',
    memorize: '<path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/>',
    sparkles: '<path d="M12 3l1.9 5.8L20 11l-6.1 2.2L12 19l-1.9-5.8L4 11l6.1-2.2Z"/><path d="M5 3v4M3 5h4M19 17v4M17 19h4"/>',
    sermon: '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6M16 13H8M16 17H8M10 9H8"/>',
    help: '<circle cx="12" cy="12" r="10"/><path d="M9.1 9a3 3 0 0 1 5.8 1c0 2-3 3-3 3M12 17h.01"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    user: '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
    log_out: '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"/>',
    log_in: '<path d="M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4M10 17l5-5-5-5M15 12H3"/>',
    radio: '<circle cx="12" cy="12" r="2"/><path d="M16.2 7.8a6 6 0 0 1 0 8.4M7.8 16.2a6 6 0 0 1 0-8.4M19.1 4.9a10 10 0 0 1 0 14.2M4.9 19.1a10 10 0 0 1 0-14.2"/>',
    phone: '<rect x="5" y="2" width="14" height="20" rx="2"/><path d="M12 18h.01"/>',
    check: '<path d="M20 6 9 17l-5-5"/>',
    lines: '<path d="M3 6h18M3 12h18M3 18h12"/>',
    word: '<path d="m5 8 6 6M4 14l6-6 2-3M2 5h12M7 2h1M22 22l-5-10-5 10M14 18h6"/>',
    rabbi: '<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>',
    commentary: '<path d="M8 21h12a2 2 0 0 0 2-2v-2H10v2a2 2 0 1 1-4 0V5a2 2 0 1 0-4 0v3h4M19 17V5a2 2 0 0 0-2-2H4"/>',
    xref: '<path d="M6 3v12M18 9a3 3 0 1 0 0-6 3 3 0 0 0 0 6ZM6 21a3 3 0 1 0 0-6 3 3 0 0 0 0 6ZM18 9a9 9 0 0 1-9 9"/>',
    prayer: '<path d="M19 14c1.5-1.5 3-3.2 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.8 0-3 .5-4.5 2-1.5-1.5-2.7-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4 3 5.5l7 7Z"/>',
    image: '<rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3-3a2 2 0 0 0-3 0L6 21"/>',
    home: '<path d="M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"/>',
    compass: '<circle cx="12" cy="12" r="10"/><path d="m16.2 7.8-2.1 6.3-6.3 2.1 2.1-6.3z"/>',
    gift: '<rect x="3" y="8" width="18" height="4" rx="1"/><path d="M12 8v13M19 12v7a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2v-7M7.5 8a2.5 2.5 0 0 1 0-5C10 3 12 8 12 8s2-5 4.5-5a2.5 2.5 0 0 1 0 5"/>',
    sync: '<path d="M21 12a9 9 0 0 0-15-6.7L3 8M3 3v5h5M3 12a9 9 0 0 0 15 6.7l3-2.7M21 21v-5h-5"/>',
    diff: '<path d="M12 3v14M5 10h14M5 21h14"/>',
    trash: '<path d="M3 6h18M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6M10 11v6M14 11v6M9 6V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2"/>',
    focus: '<path d="M3 7V5a2 2 0 0 1 2-2h2M17 3h2a2 2 0 0 1 2 2v2M21 17v2a2 2 0 0 1-2 2h-2M7 21H5a2 2 0 0 1-2-2v-2"/>',
    download: '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M7 10l5 5 5-5M12 15V3"/>',
    offline: '<path d="M12 20h.01M8.5 16.4a5 5 0 0 1 7 0M5 12.9a10 10 0 0 1 5.2-2.8M19 12.9a10 10 0 0 0-2-1.4M2 8.8a15 15 0 0 1 4.2-2.6M22 8.8a15 15 0 0 0-11.3-3.7M2 2l20 20"/>',
    globe: '<circle cx="12" cy="12" r="10"/><path d="M2 12h20M12 2a15 15 0 0 1 0 20 15 15 0 0 1 0-20"/>'
  }.freeze

  def icon(name, css: "ui-icon", label: nil)
    paths = ICONS.fetch(name.to_sym)
    attrs = { class: css, viewBox: "0 0 24 24", fill: "none", stroke: "currentColor",
              "stroke-width": 2, "stroke-linecap": "round", "stroke-linejoin": "round" }
    attrs.merge!(label ? { role: "img", "aria-label": label } : { "aria-hidden": "true" })
    content_tag(:svg, paths.html_safe, attrs) # rubocop:disable Rails/OutputSafety -- constant markup
  end

  # "John 3" / "John 3:16–18" / "Matthew 5–7" — the short label for a pane.
  def passage_label(content)
    return nil unless content&.ok?
    first, last = content.first_chapter, content.last_chapter
    label = "#{content.book.name} #{first}"
    label += "–#{last}" if last && last > first
    parsed = content.parsed
    if parsed.verse_start && !content.multi_chapter?
      label += ":#{parsed.verse_start}"
      label += "–#{parsed.verse_end}" if parsed.verse_end && parsed.verse_end != parsed.verse_start
    end
    label
  end

  # The chapter heading's two halves: book name (small caps above) and the
  # chapter number(s) set large, e.g. ["John", "3"] or ["Matthew", "5–7"].
  def chapter_heading(content)
    first, last = content.first_chapter, content.last_chapter
    number = last && last > first ? "#{first}–#{last}" : first.to_s
    [ content.book.name, number ]
  end

  # Translations a reader may pick (complete, not licence-restricted).
  def translation_choices
    @translation_choices ||= Translation.available.to_a
  end

  # The canon split by testament for the passage picker.
  def testament_books
    Bible::Canon.all.group_by(&:testament)
  end

  # Search keys for the passage picker's filter box: name, OSIS code and the
  # canon's aliases, lower-cased.
  def book_search_keys(book)
    ([ book.name, book.osis ] + Array(book.aliases)).map { |k| k.to_s.downcase.delete(" ") }.uniq.join(" ")
  end

  # The /p/ slug of the chapter before or after +chapter+ of +book+ (wrapping
  # across books), for the public passage page's prev / next links.
  def neighbor_passage_slug(book, chapter, direction)
    ref = neighbor_reference(book, chapter, direction)
    return nil unless ref
    name, number = ref.rpartition(" ").values_at(0, 2)
    target = name == book.name ? book : Book.find_by(name:)
    target && PassageSlug.slug_for(osis: target.osis_code, chapter: number.to_i)
  end
end
