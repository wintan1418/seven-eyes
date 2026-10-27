require "open-uri"
require "json"
require "set"

# Seeds reference data: the 66-book canon and public-domain translations.
#
# Bible text is sourced once from the HelloAO Free Use Bible API (one complete.json
# per translation) and written into Postgres. The running app NEVER calls this API —
# it is a seed-time data source only.
#
# Idempotent and safe to re-run:
# - the source is downloaded and parsed BEFORE any row is written, so a failed
#   download never leaves an empty Translation behind;
# - verses are written in one transaction, by upsert on
#   (translation_id, book_id, chapter, verse_number) — ids stay stable, so a
#   FORCE re-seed never trips the highlights -> verses foreign key;
# - a translation with fewer than Translation::COMPLETE_VERSE_COUNT verses is
#   treated as not seeded and is re-seeded on the next run.
class BibleSeeder
  HELLOAO = "https://bible.helloao.org/api".freeze

  # Our internal code => HelloAO translation id + metadata.
  # All entries here are public-domain or permissively licensed (CC-BY-SA or
  # ministry-friendly). NIV / NKJV / NLT / AMP / ESV / MSG are NOT here because
  # they're copyrighted and can't be self-hosted — use an on-demand API if you
  # ever need them (Phase 2+).
  TRANSLATIONS = {
    # Modern (the everyday workhorses)
    "KJV" => { id: "eng_kjv", name: "King James Version",          license: "public_domain" },
    "ASV" => { id: "eng_asv", name: "American Standard Version",   license: "public_domain" },
    "BSB" => { id: "BSB",     name: "Berean Standard Bible",       license: "public_domain" },
    "WEB" => { id: "ENGWEBP", name: "World English Bible",         license: "public_domain" },
    "NET" => { id: "eng_net", name: "NET Bible",                   license: "restricted" },
    "LSV" => { id: "eng_lsv", name: "Literal Standard Version",    license: "cc_by_sa",
               attribution: "Literal Standard Version (LSV). Copyright © 2020 by Covenant Press and the " \
                            "Covenant Christian Coalition. Licensed CC BY-SA 4.0." },
    "FBV" => { id: "eng_fbv", name: "Free Bible Version",          license: "cc_by_sa",
               attribution: "Free Bible Version (FBV). Copyright © 2018 Jonathan Gallagher. Licensed CC BY-SA 4.0." },
    "MSB" => { id: "eng_msb", name: "Majority Standard Bible",     license: "public_domain" },
    # Literal (for exegesis)
    "DBY" => { id: "eng_dby", name: "Darby Translation",           license: "public_domain" },
    "YLT" => { id: "eng_ylt", name: "Young's Literal Translation", license: "public_domain" },
    # Historic (for tradition / Catholic / accessibility)
    "GNV" => { id: "eng_gnv", name: "Geneva Bible (1599)",         license: "public_domain" },
    "DRA" => { id: "eng_dra", name: "Douay-Rheims (1899)",         license: "public_domain" },
    "WBS" => { id: "eng_wbs", name: "Webster Bible",               license: "public_domain" },
    "BBE" => { id: "eng_bbe", name: "Bible in Basic English",      license: "public_domain" }
  }.freeze

  # Readable licence names for the credits page.
  LICENSE_NAMES = {
    "public_domain" => "Public domain",
    "cc_by_sa" => "Creative Commons Attribution-ShareAlike 4.0 (CC BY-SA 4.0)",
    "restricted" => "Non-commercial use only — not offered here"
  }.freeze

  # Licence forbids commercial use without written permission (the NET Bible
  # is free for non-commercial use only). Never seeded by default and never
  # offered to readers (Translation.available) — existing rows are kept, hidden.
  RESTRICTED = %w[NET].freeze

  # Auto-seeded by `bin/rails bibles:seed` with no args. Kept conservative on
  # purpose so first-time seeders aren't waiting on 14 downloads. The rest can
  # be opted in via `bibles:seed[LSV,GNV,...]` or all at once with
  # `bibles:seed_all`.
  MVP_CODES = %w[KJV ASV BSB WEB].freeze
  ALL_CODES = (TRANSLATIONS.keys - RESTRICTED).freeze
  BATCH = 5_000

  def self.cache_dir
    Rails.root.join("tmp", "bible_cache").tap { |d| FileUtils.mkdir_p(d) }
  end

  # --- the 66-book canon (no network) ---
  def self.seed_books!
    Bible::Canon.all.each do |e|
      book = Book.find_or_initialize_by(osis_code: e.osis)
      book.update!(name: e.name, testament: e.testament, position: e.position, chapter_count: e.chapter_count)
    end
    say "Books: #{Book.count} canonical books present."
  end

  def self.seed!(codes = MVP_CODES, force: false, allow_restricted: false)
    seed_books!
    Array(codes).map(&:upcase).each do |code|
      if RESTRICTED.include?(code) && !allow_restricted
        say "#{code}: licence-restricted — not seeded."
        next
      end
      new(code, force:).run
    end
  end

  # +fetcher+ returns the HelloAO complete.json body; it defaults to a cached
  # download. Tests pass a lambda so no HTTP happens.
  def initialize(code, force: false, fetcher: nil)
    @code = code
    @meta = TRANSLATIONS.fetch(code) { raise ArgumentError, "Unknown translation #{code}" }
    @force = force
    @fetcher = fetcher || -> { download }
  end

  def run
    existing = Translation.find_by(code: @code)
    count = existing ? existing.verses.count : 0
    if existing && count >= Translation::COMPLETE_VERSE_COUNT && !@force
      existing.update_column(:verse_count, count) if existing.verse_count != count
      self.class.say "#{@code}: already seeded (#{count} verses) — skipping."
      return existing
    end
    if existing && count.positive? && count < Translation::COMPLETE_VERSE_COUNT
      self.class.say "#{@code}: only #{count} verses — incomplete, re-seeding."
    end

    rows = parse(JSON.parse(@fetcher.call)) # download + parse before touching the DB
    raise "#{@code}: the source had no verses" if rows.empty?

    translation = nil
    Translation.transaction do
      translation = Translation.find_or_initialize_by(code: @code)
      translation.assign_attributes(name: @meta[:name], language: "en", license: @meta[:license])
      translation.save!
      now = Time.current
      rows.each_slice(BATCH) do |slice|
        Verse.upsert_all(
          slice.map { |r| r.merge(translation_id: translation.id, created_at: now, updated_at: now) },
          unique_by: :index_verses_unique_location,
          update_only: %i[text]
        )
      end
      translation.update!(verse_count: translation.verses.count)
    end
    self.class.say "#{@code}: seeded #{rows.size} verses (#{translation.verse_count} in the database)."
    translation
  end

  # Flatten HelloAO's books/chapters/content into verse row hashes (without
  # translation_id). Books past the 66-book canon (DRA's deuterocanon) are skipped.
  def parse(data)
    books_by_position = Book.all.index_by(&:position)
    rows = []
    data.fetch("books", []).each do |bk|
      book = books_by_position[bk["order"]]
      next unless book

      bk.fetch("chapters", []).each do |wrapper|
        chapter = wrapper["chapter"]
        number = chapter["number"]
        chapter.fetch("content", []).each do |item|
          next unless item["type"] == "verse" && item["number"].is_a?(Integer)
          text = self.class.verse_text(item["content"])
          next if text.blank?
          rows << { book_id: book.id, chapter: number, verse_number: item["number"], text: }
        end
      end
    end
    rows.uniq { |r| [ r[:book_id], r[:chapter], r[:verse_number] ] }
  end

  CLOSERS = /\A[,.;:!?”’)\]»]/
  OPENERS = /[\s“‘(\[«]\z/

  # Join a verse's content parts into plain text. Parts are strings or objects
  # ({ "text" => "...", "wordsOfJesus" => true } or { "noteId" => N } footnote
  # markers). Parts are joined with a space except where the next part opens
  # with closing punctuation or the previous ends with an opening quote, so
  # "heel." + "”" reads "heel.”" not "heel. ”". LSV's "||" poetry-line marks
  # and pilcrows are dropped; whitespace is normalised.
  def self.verse_text(parts)
    pieces = Array(parts).filter_map { |p| p.is_a?(String) ? p : p["text"] }
                         .map { |t| t.gsub("¶", "").gsub("||", " ").gsub(/\s+/, " ").strip }
                         .reject(&:empty?)
    pieces.each_with_object(+"") do |piece, out|
      out << " " unless out.empty? || out.match?(OPENERS) || piece.match?(CLOSERS)
      out << piece
    end.gsub(/\s+/, " ").strip
  end

  VerifyRow = Struct.new(:code, :name, :verse_count, :books, :missing_books, :missing_chapters, :restricted,
                         keyword_init: true) do
    def complete? = verse_count >= Translation::COMPLETE_VERSE_COUNT && missing_books.empty? && missing_chapters.empty?
  end

  # Per-translation health check against Bible::Canon: verse total, books
  # present, and every chapter the canon expects that the DB lacks.
  def self.verify
    expected = Bible::Canon.all.to_h { |e| [ e.osis, e.chapter_count ] }
    osis_by_id = Book.unscoped.pluck(:id, :osis_code).to_h
    Translation.unscoped.order(:id).map do |t|
      present = Hash.new { |h, k| h[k] = Set.new }
      Verse.where(translation_id: t.id).distinct.pluck(:book_id, :chapter).each do |book_id, chapter|
        present[osis_by_id[book_id]] << chapter
      end
      missing_chapters = expected.flat_map do |osis, n|
        next [] unless present.key?(osis) # reported as a missing book instead
        (1..n).reject { |c| present[osis].include?(c) }.map { |c| "#{osis} #{c}" }
      end
      VerifyRow.new(code: t.code, name: t.name, verse_count: Verse.where(translation_id: t.id).count,
                    books: present.size, missing_books: expected.keys - present.keys,
                    missing_chapters:, restricted: RESTRICTED.include?(t.code))
    end
  end

  def self.say(msg)
    Rails.logger.info("[BibleSeeder] #{msg}")
    puts "[BibleSeeder] #{msg}" if $stdout.tty? || Rails.env.local?
  end

  private

  def download
    path = self.class.cache_dir.join("#{@meta[:id]}.json")
    return File.read(path, encoding: "UTF-8") if File.exist?(path) && File.size(path).positive?
    url = "#{HELLOAO}/#{@meta[:id]}/complete.json"
    self.class.say "Downloading #{@code} from #{url} ..."
    body = URI.parse(url).open(read_timeout: 120, &:read).force_encoding("UTF-8")
    File.binwrite(path, body)
    body
  end
end
