# The offline word pack: everything root-word projection needs with no
# signal — the KJV's Strong's tags for every verse and the lexicon entries
# they name — as one gzipped JSON document the device keeps in IndexedDB
# (app/javascript/lib/offline/word_pack.js). The Bible bundles leave tokens
# out (OfflineBundle) so a reader who never projects a word never pays for it.
#
#   {
#     "format": 1, "version": "…", "translation": "KJV",
#     "lexicon": { "G25": ["ἀγαπάω", "agapáō", null, "to love …", "(be-)love(-ed)", "perhaps from …", 143], … },
#     "books": [ { "osis": "John", "prefix": "G", "chapters": [ ["verse 1", "verse 2", …], … ] }, … ]
#   }
#
# A verse is its tokens joined back into one string with each tagged word
# followed by "@" and its number ("For@1063 God@2316 so@3779 loved@25 the
# world@2889, …"); the testament gives the H/G prefix. Lexicon rows follow
# LEXICON_FIELDS. Only entries the KJV actually uses are included.
class RootWordPack
  FORMAT = 1
  CACHE_DIR = OfflineBundle::CACHE_DIR
  LEXICON_FIELDS = %w[ lemma translit pron def kjv deriv n ].freeze

  attr_reader :translation

  def initialize(translation = RootWords.kjv)
    @translation = translation
  end

  def available? = translation.present?

  def summary
    { version: version, size: gzip.bytesize, bytes: raw_bytesize, translation: translation.code }
  end

  # Changes whenever the KJV text/tokens or the lexicon change.
  def version
    @version ||= Rails.cache.fetch([ "root_word_pack_version", FORMAT, translation.id ], expires_in: 10.minutes) do
      count, latest = LexiconEntry.pick(Arel.sql("COUNT(*)"), Arel.sql("MAX(updated_at)"))
      Digest::SHA256.hexdigest([ FORMAT, OfflineBundle.new(translation).version, count, latest&.utc&.iso8601(6) ].join("|"))[0, 16]
    end
  end

  def gzip
    @gzip ||= read_cache || write_cache
  end

  def json
    @json ||= ActiveSupport::Gzip.decompress(gzip)
  end

  def to_h
    rows = Verse.where(translation_id: translation.id).joins(:book)
                .order("books.position", "verses.chapter", "verses.verse_number")
                .pluck("books.osis_code", "verses.chapter", "verses.verse_number", "verses.tokens")
    old_testament = Book.testament_old.pluck(:osis_code).to_set
    books = rows.chunk_while { |a, b| a[0] == b[0] }.map do |book_rows|
      chapters = []
      book_rows.each do |_osis, chapter, number, tokens|
        verses = (chapters[chapter - 1] ||= [])
        verses[number - 1] = self.class.encode_verse(tokens)
      end
      chapters.map! { |vs| vs && vs.map(&:to_s) }
      osis = book_rows.first[0]
      { osis: osis, prefix: old_testament.include?(osis) ? "H" : "G", chapters: chapters.map { |c| c || [] } }
    end

    totals = RootWords.counts(translation)
    lexicon = LexiconEntry.where(strongs: totals.keys).each_with_object({}) do |e, out|
      j = RootWords.entry_json(e, totals[e.strongs])
      out[e.strongs] = LEXICON_FIELDS.map { |f| j[f.to_sym].presence }
    end

    { format: FORMAT, version: version, translation: translation.code, fields: LEXICON_FIELDS,
      lexicon: lexicon, books: books }
  end

  # Tokens → "For@1063 God@2316 …". Untagged pieces stay as they are; a
  # tagged one gets "@<number>" (prefix dropped — the testament says which).
  def self.encode_verse(tokens)
    Array(tokens).map do |t|
      w = t["w"].to_s.delete("@")
      s = t["s"].to_s[/\d+[a-z]?\z/i]
      s ? "#{w}@#{s}" : w
    end.join
  end

  private

  def raw_bytesize
    meta_path.exist? ? meta_path.read.to_i : json.bytesize
  end

  def cache_path = CACHE_DIR.join("rootwords-#{translation.code}-#{version}.json.gz")
  def meta_path = CACHE_DIR.join("rootwords-#{translation.code}-#{version}.bytes")

  def read_cache
    cache_path.binread if cache_path.exist?
  end

  def write_cache
    body = to_h.to_json
    compressed = ActiveSupport::Gzip.compress(body, Zlib::BEST_COMPRESSION)
    FileUtils.mkdir_p(CACHE_DIR)
    tmp = CACHE_DIR.join("rootwords-#{translation.code}-#{version}.#{SecureRandom.hex(4)}.tmp")
    File.binwrite(tmp, compressed)
    File.rename(tmp, cache_path)
    File.write(meta_path, body.bytesize.to_s)
    Dir.glob(CACHE_DIR.join("rootwords-#{translation.code}-*.{gz,bytes}")).each do |f|
      FileUtils.rm_f(f) unless f.include?("-#{version}.")
    end
    @json = body
    compressed
  end
end
