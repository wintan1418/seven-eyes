require "open-uri"

# Seeds the Treasury of Scripture Knowledge (TSK) cross-references from OpenBible.info
# (public domain, ~344k verse-to-verse links). Seed-time data source only.
#
# Source rows are TSV: "From Verse \t To Verse \t Votes", OSIS dotted refs
# (Gen.1.1, ranges as John.1.1-John.1.3). We filter votes >= min_votes.
class CrossReferenceSeeder
  URL = "https://a.openbible.info/data/cross-references.zip".freeze
  ENTRY = "cross_references.txt".freeze
  BATCH = 10_000

  def self.cache_dir
    Rails.root.join("tmp", "bible_cache").tap { |d| FileUtils.mkdir_p(d) }
  end

  def self.seed!(force: false, min_votes: 0)
    new(force:, min_votes:).run
  end

  def initialize(force: false, min_votes: 0)
    @force = force
    @min_votes = min_votes
  end

  def run
    if CrossReference.exists? && !@force
      say "Cross-references already seeded (#{CrossReference.count}) — skipping."
      return
    end
    CrossReference.delete_all if @force

    books = Book.all.index_by(&:osis_code)
    now = Time.current
    buffer = []
    total = 0
    skipped = 0

    each_data_line do |line|
      from, to, votes = line.split("\t")
      votes = votes.to_i
      next if votes < @min_votes

      fb, fc, fv = from.split(".")
      from_book = books[fb]
      next unless from_book && fc && fv

      to_start, to_end = to.split("-")
      tb, tc, tv = to_start.split(".")
      to_book = books[tb]
      next unless to_book && tc && tv

      tc_end = tv_end = nil
      if to_end
        _eb, ec, ev = to_end.split(".")
        tc_end = ec.to_i
        tv_end = ev.to_i
      end

      buffer << {
        from_book_id: from_book.id, from_chapter: fc.to_i, from_verse: fv.to_i,
        to_book_id: to_book.id, to_chapter_start: tc.to_i, to_verse_start: tv.to_i,
        to_chapter_end: tc_end, to_verse_end: tv_end, votes:,
        created_at: now, updated_at: now
      }

      if buffer.size >= BATCH
        CrossReference.insert_all(buffer)
        total += buffer.size
        buffer = []
      end
    end

    unless buffer.empty?
      CrossReference.insert_all(buffer)
      total += buffer.size
    end
    say "Cross-references: seeded #{total} (min_votes=#{@min_votes})."
    total
  end

  private

  def each_data_line
    path = ensure_extracted
    first = true
    File.foreach(path) do |line|
      if first
        first = false
        next # header
      end
      line = line.strip
      yield line unless line.empty?
    end
  end

  def ensure_extracted
    txt = self.class.cache_dir.join(ENTRY)
    return txt if txt.exist? && !@force_download

    zip = self.class.cache_dir.join("cross-references.zip")
    unless zip.exist?
      say "Downloading TSK cross-references from #{URL} ..."
      body = URI.parse(URL).open(read_timeout: 120, &:read)
      File.binwrite(zip, body)
    end
    say "Extracting #{ENTRY} ..."
    extracted = IO.popen([ "unzip", "-p", zip.to_s, ENTRY ], &:read)
    raise "Failed to extract #{ENTRY} (is `unzip` installed?)" if extracted.blank?
    File.write(txt, extracted)
    txt
  end

  def say(msg)
    Rails.logger.info("[CrossReferenceSeeder] #{msg}")
    puts "[CrossReferenceSeeder] #{msg}" if $stdout.tty? || Rails.env.local?
  end
end
