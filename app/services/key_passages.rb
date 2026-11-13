# Turns a short list of references ("Ephesians 2:8-9", "Acts 4:12") into
# passages with their words from our own Bible text, ready to show and to link
# into the reader (/p/:slug/open). References that don't parse or aren't in the
# translation are left out — the page never shows an empty quote.
#
#   KeyPassages.call([ "John 3:16" ]) =>
#     [ #<Passage label="John 3:16", text="For God so loved…", slug="john-3-16", translation_code="KJV"> ]
module KeyPassages
  Passage = Struct.new(:label, :text, :slug, :translation_code, keyword_init: true)

  module_function

  def call(references, translation: default_translation)
    return [] unless translation

    Array(references).filter_map { |ref| resolve(ref, translation) }
  end

  # The glossary quotes the KJV, the text its Strong's numbers are tagged in.
  def default_translation
    Translation.find_by(code: RootWords::TRANSLATION) || Translation.default
  end

  def resolve(reference, translation)
    parsed = ReferenceParser.call(reference.to_s)
    return nil unless parsed.valid? && parsed.verse_start

    book = Book.find_by_osis(parsed.osis)
    return nil unless book

    verses = Verse.for_reference(parsed, translation:, book:).to_a
    return nil if verses.empty?

    Passage.new(label: parsed.label, text: verses.map(&:text).join(" "),
                slug: PassageSlug.slug_from_result(parsed), translation_code: translation.code)
  end
end
