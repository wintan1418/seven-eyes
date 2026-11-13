# Root words for preach mode: a verse's Strong's-tagged KJV words with their
# lexicon entries, so the operator can put "the Greek word here is agapē" on
# the big screen. The KJV is the tagged text (VerseTokenSeeder); any other
# translation maps through the KJV verse with the same reference.
#
# Entries go out in one compact shape, shared with the offline word pack
# (RootWordPack) and read by app/javascript/lib/root_words.js:
#
#   { s: "G25", lemma: "ἀγαπάω", translit: "agapáō", pron: nil,
#     def: "to love (in a social or moral sense)", kjv: "(be-)love(-ed)",
#     deriv: "perhaps from …", n: 143 }
#
# n is how many times the number is tagged in the KJV.
module RootWords
  TRANSLATION = "KJV"
  LIMITS = { def: 360, kjv: 240, deriv: 200 }.freeze

  module_function

  def kjv
    Translation.find_by(code: TRANSLATION)
  end

  # strongs → occurrences in the KJV, computed once per version of its text.
  def counts(translation = kjv)
    return {} unless translation
    version = OfflineBundle.new(translation).version
    Rails.cache.fetch([ "root_words/counts", translation.id, version ], expires_in: 1.day) do
      sql = <<~SQL.squish
        SELECT t->>'s', COUNT(*) FROM verses, jsonb_array_elements(verses.tokens) AS t
        WHERE verses.translation_id = $1 AND verses.tokens IS NOT NULL AND t ? 's'
        GROUP BY 1
      SQL
      ActiveRecord::Base.connection.exec_query(sql, "RootWords counts", [ translation.id ])
                        .rows.to_h { |s, n| [ s, n.to_i ] }
    end
  end

  def entry_json(entry, count)
    {
      s: entry.strongs, lemma: entry.lemma.to_s, translit: entry.translit.to_s, pron: entry.pron.presence,
      def: entry.definition.to_s.squish.truncate(LIMITS[:def]),
      kjv: entry.kjv_def.to_s.squish.truncate(LIMITS[:kjv]),
      deriv: entry.derivation.to_s.squish.truncate(LIMITS[:deriv]),
      n: count.to_i
    }
  end

  # One verse: its KJV tokens (every piece of text, tagged or not) and the
  # entries they name. nil when the reference or the KJV verse doesn't exist.
  def verse(osis:, chapter:, verse:)
    book = Book.find_by_osis(osis)
    translation = kjv
    return nil unless book && translation

    row = Verse.find_by(translation:, book:, chapter: chapter.to_i, verse_number: verse.to_i)
    return nil unless row

    tokens = Array(row.tokens).map { |t| t["s"].present? ? { w: t["w"].to_s, s: t["s"] } : { w: t["w"].to_s } }
    numbers = tokens.filter_map { |t| t[:s] }.uniq
    totals = counts(translation)
    entries = LexiconEntry.where(strongs: numbers).index_by(&:strongs)
    {
      ok: true,
      reference: "#{Bible::Canon.find(book.osis_code)&.name || book.name} #{row.chapter}:#{row.verse_number}",
      osis: book.osis_code, chapter: row.chapter, verse: row.verse_number,
      translation: translation.code, text: row.text,
      tagged: tokens.any? { |t| t[:s] },
      tokens: tokens,
      entries: entries.transform_values { |e| entry_json(e, totals[e.strongs]) }
    }
  end
end
