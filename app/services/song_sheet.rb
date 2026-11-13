# A song's words → the slides the projector walks through, EasyWorship-style.
# The device has the same rules in app/javascript/lib/song_sheet.js (it projects
# offline); keep the two in step — test/fixtures/files/song_sheet_cases.json runs
# against both.
#
# Blank lines split the words into stanzas; each stanza is one slide. A stanza
# may start with a section label on its own line — "[Verse 1]", "[Chorus]",
# "[Pre-Chorus]", "[Bridge]", "[Tag]", any "[Name]" in brackets, or the usual
# bare words ("Verse 1", "Chorus:", "Refrain", "(Chorus x2)", "V1:"). A label
# with no words under it repeats that section there. A song with no labels at
# all is projected stanza by stanza, exactly as before sections existed.
#
# The arrangement ("V1 C V2 C B C") projects a section as often as it is named.
# Without one, a hymn-shaped song (verses + one chorus written once) sings the
# chorus after every verse; any other song follows the written order.
#
#   SongSheet.new(body, arrangement).slides  → [Slide(label, code, text)]
#   #unknown → arrangement names that matched nothing
class SongSheet
  Slide = Data.define(:label, :code, :text)
  Section = Struct.new(:kind, :key, :label, :code, :text, :ref, keyword_init: true)

  KINDS = [
    # kind, display name, short code, words that name it
    [ "prechorus", "Pre-Chorus", "PC", %w[prechorus pre pc] ],
    [ "verse", "Verse", "V", %w[verse stanza v] ],
    [ "chorus", "Chorus", "C", %w[chorus refrain ch c r] ],
    [ "bridge", "Bridge", "B", %w[bridge br b] ],
    [ "tag", "Tag", "T", %w[tag t] ],
    [ "ending", "Ending", "E", %w[ending end outro coda e o] ],
    [ "intro", "Intro", "I", %w[intro i] ],
    [ "vamp", "Vamp", "VP", %w[vamp vp] ]
  ].freeze
  BY_WORD = KINDS.each_with_object({}) { |(kind, name, code, words), h| words.each { |w| h[w] = { kind:, name:, code: } } }.freeze

  LONG_WORDS = "pre-?chorus|pre chorus|verse|stanza|chorus|refrain|bridge|tag|ending|outro|coda|intro|vamp"
  REPEAT = '(?:[x×]\s*\d+|\d+\s*[x×]|\(\s*[x×]?\s*\d+\s*[x×]?\s*\)|\(?\s*repeat\s*\)?)'
  BARE_LABEL = /\A\(?\s*(?:repeat\s+(?:the\s+)?)?(#{LONG_WORDS})\s*(\d+)?\s*#{REPEAT}?\s*\)?\s*[:.]?\z/i
  SHORT_LABEL = /\A(pc|v|c|ch|b|br|t|e)\s*(\d+)?\s*:\z/i
  BRACKET_LABEL = /\A\[\s*([^\]]{1,30}?)\s*\]\z/
  BRACKET_INNER = /\A(?:repeat\s+(?:the\s+)?)?(#{LONG_WORDS}|pc|v|c|ch|b|br|t|e)\s*(\d+)?\s*#{REPEAT}?\z/i

  attr_reader :unknown

  def self.label_for(line)
    text = line.to_s.strip
    return nil if text.empty? || text.length > 40
    if (bracket = text.match(BRACKET_LABEL))
      inner = bracket[1].strip
      known = inner.match(BRACKET_INNER)
      return known ? known_label(known[1], known[2]) : { kind: "other", number: nil, name: inner }
    end
    bare = text.match(BARE_LABEL) || text.match(SHORT_LABEL)
    bare && known_label(bare[1], bare[2])
  end

  def self.known_label(word, digits)
    defn = BY_WORD[word.downcase.gsub(/[\s-]/, "")]
    defn && { kind: defn[:kind], number: digits&.to_i, name: defn[:name] }
  end

  def initialize(body, arrangement = nil)
    @body = body.to_s
    @arrangement = arrangement.to_s
    @unknown = []
  end

  def labelled?
    sections
    @labelled
  end

  def slides
    @slides ||= build_slides
  end

  # The words in projection order, labels dropped — what live followers get.
  def projected_body
    slides.map(&:text).reject(&:empty?).join("\n\n")
  end

  def flow_codes
    slides.map { |s| s.code || "·" }.join(" ")
  end

  private

  def blocks
    @body.gsub(/\r\n?/, "\n").split(/\n[ \t]*\n/).map(&:strip).reject(&:empty?)
  end

  def sections
    @sections ||= begin
      raw = blocks.map do |block|
        first, rest = block.split("\n", 2)
        label = self.class.label_for(first)
        label ? { label:, text: rest.to_s.strip } : { label: nil, text: block }
      end
      @labelled = raw.any? { |b| b[:label] }
      @defined = {}
      @labelled ? labelled_sections(raw) : raw.map { |b| Section.new(text: b[:text]) }
    end
  end

  def labelled_sections(raw)
    list = []
    verse_max = 0
    carry = nil
    raw.each do |b|
      label = b[:label]
      if label && b[:text].empty?
        key = key_of(label, verse_max, looking_up: true)
        key && @defined.key?(key) ? list << Section.new(ref: key) : carry = label
        next
      end
      label ||= carry
      carry = nil
      label ||= { kind: "verse", number: nil, name: "Verse" }
      number = label[:kind] == "verse" ? (label[:number] || verse_max + 1) : label[:number]
      verse_max = [ verse_max, number ].max if label[:kind] == "verse"
      section = describe(label.merge(number:), b[:text])
      @defined[section.key] ||= section
      list << section
    end
    list
  end

  def key_of(label, verse_max = 0, looking_up: false)
    return "other:#{label[:name].downcase}" if label[:kind] == "other"
    if label[:kind] == "verse"
      n = label[:number] || (looking_up ? verse_max : verse_max + 1)
      return n.to_i.positive? ? "v#{n}" : nil
    end
    code = KINDS.find { |k| k[0] == label[:kind] }[2].downcase
    label[:number].to_i > 1 ? "#{code}#{label[:number]}" : code
  end

  def describe(label, text)
    return Section.new(kind: "other", key: key_of(label), label: label[:name], code: label[:name], text:) if label[:kind] == "other"
    defn = KINDS.find { |k| k[0] == label[:kind] }
    numbered = label[:kind] == "verse" || label[:number].to_i > 1
    Section.new(kind: label[:kind], key: key_of(label), text:,
                label: numbered ? "#{defn[1]} #{label[:number]}" : defn[1],
                code: numbered ? "#{defn[2]}#{label[:number]}" : defn[2])
  end

  def build_slides
    list = sections
    to_slide = ->(s) { Slide.new(label: s.label, code: s.code, text: s.text) }
    return list.map(&to_slide) unless @labelled

    flow = arrangement_flow
    return flow.map(&to_slide) if flow.any?

    written = list.map { |s| s.ref ? @defined[s.ref] : s }.compact
    with_refrain(written, list).map(&to_slide)
  end

  # Hymn shape — verses plus one chorus written once, never repeated by hand —
  # sings the chorus after every verse.
  def with_refrain(written, list)
    choruses = list.select { |s| s.ref || s.kind == "chorus" }
    others = list.reject { |s| s.ref || s.kind == "chorus" }
    return written unless choruses.size == 1 && !choruses.first.ref && others.any? && others.all? { |s| s.kind == "verse" }
    chorus = choruses.first
    written.each_with_index.flat_map do |s, i|
      s.kind == "verse" && !written[i + 1].equal?(chorus) ? [ s, chorus ] : [ s ]
    end
  end

  def arrangement_tokens
    cleaned = @arrangement.downcase
                          .gsub(/pre[\s-]+chorus/, "prechorus")
                          .gsub(/\(?\s*[x×]\s*\d+\s*\)?|\b\d+\s*[x×]\b|\*\s*\d+/, " ")
    cleaned.split(/[\s,;|\/>→·–—-]+/).reject(&:empty?).each_with_object([]) do |part, tokens|
      if part.match?(/\A\d+\z/) && tokens.any? && !tokens.last.match?(/\d\z/)
        tokens[-1] += part
      else
        tokens << part
      end
    end
  end

  def arrangement_flow
    last_verse = 0
    arrangement_tokens.filter_map do |token|
      next @defined["other:#{token}"] if @defined.key?("other:#{token}")
      m = token.match(/\A([a-z]+)(\d*)\z/)
      defn = m && BY_WORD[m[1]]
      unless defn
        @unknown << token
        next
      end
      key = if defn[:kind] == "verse"
        last_verse = m[2].empty? ? last_verse + 1 : m[2].to_i
        "v#{last_verse}"
      else
        key_of({ kind: defn[:kind], number: m[2].empty? ? nil : m[2].to_i })
      end
      section = @defined[key]
      @unknown << token unless section
      section
    end
  end
end
