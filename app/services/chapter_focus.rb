# "Open at verse": a reference to one or more verses inside one chapter opens
# as the whole chapter with those verses marked (like a Bible app's search
# results). Anything else — a whole chapter, a span across chapters, "ff",
# nonsense — opens as it is.
#
#   ChapterFocus.call("Deut 32:2-4")  # => #<struct reference="Deuteronomy 32", verses="2-4">
#   ChapterFocus.call("John 3")       # => #<struct reference="John 3", verses=nil>
class ChapterFocus
  Result = Struct.new(:reference, :verses) do
    def focus? = verses.present?
  end

  VERSES = /\A\d{1,3}(?:-\d{1,3})?\z/

  def self.call(reference)
    parsed = ReferenceParser.call(reference.to_s)
    return Result.new(reference.to_s.strip, nil) unless parsed.valid?
    return Result.new(parsed.label, nil) if parsed.verse_start.nil? || parsed.multi_chapter? || parsed.open_ended?

    last = parsed.verse_end || parsed.verse_start
    verses = last > parsed.verse_start ? "#{parsed.verse_start}-#{last}" : parsed.verse_start.to_s
    Result.new("#{parsed.book_name} #{parsed.chapter}", verses)
  end

  # A ?verse= value we may render into the page ("2" / "2-4"), else nil.
  def self.clean(value)
    value.to_s[VERSES]
  end
end
