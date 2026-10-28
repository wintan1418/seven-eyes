# One whole translation as a compact JSON document the reader stores on the
# device (IndexedDB) so Scripture opens with no signal. Only translations
# readers may choose (Translation.available) are ever bundled — licence-
# restricted texts (NET) never leave the server.
#
#   {
#     "format": 1, "code": "KJV", "id": 1, "name": "King James Version",
#     "display_name": "King James Version", "vulgate": false, "version": "3f9c…",
#     "books": [
#       { "osis": "Gen", "chapters": [ { "i": 1, "t": ["In the beginning…", …] }, … ] },
#       …
#     ]
#   }
#
# A chapter holds its verse texts in order ("t"). "i" is the id of the first
# verse when the ids run consecutively (they do for a seeded translation),
# otherwise every verse's id; "n" lists the verse numbers only when they are
# not simply 1..N (a translation that omits a verse). Strong's tokens are left
# out: they would roughly triple the download for one feature (word study).
#
# The bundle is built once per version and kept gzipped under tmp/, so serving
# it is a file read. The version changes whenever the translation's text does.
class OfflineBundle
  FORMAT = 1
  CACHE_DIR = Rails.root.join("tmp", "offline_bundles")

  attr_reader :translation

  def initialize(translation)
    @translation = translation
  end

  # Every translation a reader may download, with its size and version.
  def self.manifest
    Translation.available.map { |t| new(t).summary }
  end

  def summary
    {
      code: translation.code,
      id: translation.id,
      name: translation.name,
      display_name: translation.display_name,
      vulgate: translation.vulgate_numbering?,
      version: version,
      size: gzip.bytesize,
      bytes: raw_bytesize
    }
  end

  # Changes whenever a verse of this translation is added, removed or edited.
  def version
    @version ||= Rails.cache.fetch([ "offline_bundle_version", FORMAT, translation.id ], expires_in: 10.minutes) do
      count, latest = Verse.where(translation_id: translation.id).pick(Arel.sql("COUNT(*)"), Arel.sql("MAX(updated_at)"))
      Digest::SHA256.hexdigest([ FORMAT, translation.id, translation.code, translation.name,
                                 count, latest&.utc&.iso8601(6) ].join("|"))[0, 16]
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
                .pluck("books.osis_code", "verses.chapter", "verses.verse_number", "verses.id", "verses.text")

    books = rows.chunk_while { |a, b| a[0] == b[0] }.map do |book_rows|
      chapters = []
      book_rows.chunk_while { |a, b| a[1] == b[1] }.each do |chapter_rows|
        chapters[chapter_rows.first[1] - 1] = encode_chapter(chapter_rows)
      end
      { osis: book_rows.first[0], chapters: chapters }
    end

    {
      format: FORMAT, code: translation.code, id: translation.id, name: translation.name,
      display_name: translation.display_name, vulgate: translation.vulgate_numbering?,
      version: version, books: books
    }
  end

  private

  def encode_chapter(rows)
    nums = rows.map { |r| r[2] }
    ids = rows.map { |r| r[3] }
    chapter = { i: consecutive?(ids) ? ids.first : ids, t: rows.map { |r| r[4].to_s } }
    chapter[:n] = nums unless nums == (1..nums.size).to_a
    chapter
  end

  def consecutive?(ids) = ids.each_cons(2).all? { |a, b| b == a + 1 }

  def raw_bytesize
    meta_path.exist? ? meta_path.read.to_i : json.bytesize
  end

  def cache_path = CACHE_DIR.join("#{translation.code}-#{version}.json.gz")
  def meta_path = CACHE_DIR.join("#{translation.code}-#{version}.bytes")

  def read_cache
    cache_path.binread if cache_path.exist?
  end

  def write_cache
    body = to_h.to_json
    compressed = ActiveSupport::Gzip.compress(body, Zlib::BEST_COMPRESSION)
    FileUtils.mkdir_p(CACHE_DIR)
    tmp = CACHE_DIR.join("#{translation.code}-#{version}.#{SecureRandom.hex(4)}.tmp")
    File.binwrite(tmp, compressed)
    File.rename(tmp, cache_path) # atomic: a concurrent reader never sees half a file
    File.write(meta_path, body.bytesize.to_s)
    # Older versions of this translation are dead weight once a new one exists.
    # (Another process may be doing the same, or still writing: leave .tmp files.)
    Dir.glob(CACHE_DIR.join("#{translation.code}-*.{gz,bytes}")).each do |f|
      FileUtils.rm_f(f) unless f.include?("-#{version}.")
    end
    @json = body
    compressed
  end
end
