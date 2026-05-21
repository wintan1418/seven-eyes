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

  def translation_options(selected_id)
    options_from_collection_for_select(Translation.all, :id, :code, selected_id)
  end

  # Render one verse as the design's superscript-number + text. When +dropcap+ is
  # set and the verse opens with a letter, the first letter becomes an illuminated
  # drop cap (manuscript style) and the verse text continues after it.
  def scripture_verse(verse, dropcap: false)
    vnum = tag.span(verse.verse_number, class: "ps-vnum")
    text = verse.text.to_s

    if dropcap && text.match?(/\A\p{Alpha}/)
      cap = tag.span(text[0], class: "ps-dropcap")
      verse_span = tag.span(safe_join([ vnum, text[1..], " " ]), class: "ps-verse")
      safe_join([ cap, verse_span ])
    else
      tag.span(safe_join([ vnum, text, " " ]), class: "ps-verse")
    end
  end
end
