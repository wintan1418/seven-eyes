# Loads TSK cross-references for a verse, paired with a preview of each target
# verse's text in a chosen translation — all in two queries (refs + one batched
# verse fetch), never one query per reference.
class CrossReferenceLookup
  Row = Struct.new(:reference, :preview, :votes, keyword_init: true)

  def self.for_verse(book:, chapter:, verse:, translation:, limit: 60)
    refs = CrossReference.for_verse(book_id: book.id, chapter:, verse:)
                         .includes(:to_book).limit(limit).to_a
    previews = preview_map(refs, translation)
    refs.map do |r|
      Row.new(
        reference: r.to_label,
        preview: previews[[ r.to_book_id, r.to_chapter_start, r.to_verse_start ]],
        votes: r.votes
      )
    end
  end

  def self.preview_map(refs, translation)
    return {} if refs.empty? || translation.nil?

    tuples = refs.map { |r| [ r.to_book_id, r.to_chapter_start, r.to_verse_start ] }.uniq
    placeholders = ([ "(?, ?, ?)" ] * tuples.size).join(", ")
    Verse.where(translation: translation)
         .where("(book_id, chapter, verse_number) IN (#{placeholders})", *tuples.flatten)
         .each_with_object({}) do |v, map|
           map[[ v.book_id, v.chapter, v.verse_number ]] = v.text
         end
  end
end
