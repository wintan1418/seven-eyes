# Compiles a study into a printable / markdown sermon manuscript.
# Walks the study's panes in position order, resolves their references via
# Pane#content (already used in the workspace), and bundles each pane's verses,
# notes, and the user's highlights into a Section.
class SermonManuscript
  Section = Struct.new(
    :position, :numeral, :ref_title, :translation, :verses, :notes, :highlights,
    keyword_init: true
  )

  ROMAN = { 100 => "C", 90 => "XC", 50 => "L", 40 => "XL", 10 => "X",
            9 => "IX", 5 => "V", 4 => "IV", 1 => "I" }.freeze

  attr_reader :study, :sections

  def initialize(study, current_user: nil)
    @study = study
    @current_user = current_user
    @sections = build_sections
  end

  def title
    study.name.presence || "Untitled Study"
  end

  def compiled_on
    Date.current
  end

  def to_markdown
    out = []
    out << "# #{title}"
    out << ""
    out << "*Compiled #{compiled_on.strftime('%B %-d, %Y')}*"
    out << ""

    if sections.empty?
      out << "_No verses to compile yet — add references to your panes._"
    else
      sections.each_with_index do |s, i|
        out << "## #{s.numeral}. #{s.ref_title} _(#{s.translation})_"
        out << ""
        s.verses.each do |v|
          out << "> **#{v.verse_number}** #{v.text.to_s.strip}"
        end
        out << ""
        if s.notes.present?
          out << "**Reflections**"
          out << ""
          out << s.notes
          out << ""
        end
        out << "---" unless i == sections.size - 1
        out << ""
      end
    end

    out.join("\n")
  end

  private

  def build_sections
    study.panes.order(:position).filter_map do |pane|
      content = pane.content
      next unless content.ok?

      hls = highlights_for(content.verses)
      Section.new(
        position: pane.position,
        numeral: roman(pane.position + 1),
        ref_title: ref_title(content),
        translation: content.translation.code,
        verses: content.verses,
        notes: pane.notes.to_s.strip,
        highlights: hls
      )
    end
  end

  def ref_title(content)
    parsed = content.parsed
    chapter = parsed.chapter
    base = "#{content.book.name} #{chapter}"
    return base if parsed.verse_start.blank?
    return "#{base}:#{parsed.verse_start}" if parsed.verse_end.blank? || parsed.verse_end == parsed.verse_start
    "#{base}:#{parsed.verse_start}-#{parsed.verse_end}"
  end

  def highlights_for(verses)
    return {} unless @current_user
    @current_user.highlights.where(verse_id: verses.map(&:id)).group_by(&:verse_id)
  end

  def roman(n)
    return n.to_s if n > 89
    out = +""
    rem = n
    ROMAN.each do |v, l|
      while rem >= v
        out << l
        rem -= v
      end
    end
    out
  end
end
