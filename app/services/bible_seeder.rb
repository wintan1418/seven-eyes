require "open-uri"
require "json"

# Seeds reference data: the 66-book canon and public-domain translations.
#
# Bible text is sourced once from the HelloAO Free Use Bible API (one complete.json
# per translation) and written into Postgres. The running app NEVER calls this API —
# it is a seed-time data source only. Idempotent: re-running skips already-seeded
# translations unless force: true.
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
    "NET" => { id: "eng_net", name: "NET Bible",                   license: "permissive" },
    "LSV" => { id: "eng_lsv", name: "Literal Standard Version",    license: "cc_by_sa" },
    "FBV" => { id: "eng_fbv", name: "Free Bible Version",          license: "cc_by_sa" },
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

  # Auto-seeded by `bin/rails bibles:seed` with no args. Kept conservative on
  # purpose so first-time seeders aren't waiting on 14 downloads. The rest can
  # be opted in via `bibles:seed[NET,LSV,GNV,...]` or all at once with
  # `bibles:seed_all`.
  MVP_CODES = %w[KJV ASV BSB WEB].freeze
  ALL_CODES = TRANSLATIONS.keys.freeze
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

  def self.seed!(codes = MVP_CODES, force: false)
    seed_books!
    Array(codes).map(&:upcase).each { |code| new(code, force:).run }
  end

  def initialize(code, force: false)
    @code = code
    @meta = TRANSLATIONS.fetch(code) { raise ArgumentError, "Unknown translation #{code}" }
    @force = force
  end

  def run
    translation = Translation.find_or_initialize_by(code: @code)
    if translation.persisted? && translation.verses.exists? && !@force
      self.class.say "#{@code}: already seeded (#{translation.verses.count} verses) — skipping."
      return translation
    end
    translation.assign_attributes(name: @meta[:name], language: "en", license: @meta[:license])
    translation.save!
    translation.verses.delete_all if @force

    data = JSON.parse(download)
    books_by_position = Book.all.index_by(&:position)
    now = Time.current
    total = 0
    buffer = []

    data["books"].each do |bk|
      book = books_by_position[bk["order"]]
      next unless book

      bk["chapters"].each do |wrapper|
        chapter = wrapper["chapter"]
        number = chapter["number"]
        chapter["content"].each do |item|
          next unless item["type"] == "verse"
          text = self.class.verse_text(item["content"])
          next if text.blank?
          buffer << {
            translation_id: translation.id, book_id: book.id,
            chapter: number, verse_number: item["number"], text:,
            created_at: now, updated_at: now
          }
          if buffer.size >= BATCH
            flush(buffer)
            total += buffer.size
            buffer = []
          end
        end
      end
    end
    flush(buffer)
    total += buffer.size
    self.class.say "#{@code}: seeded #{total} verses."
    translation
  end

  # Join a verse's content parts into plain text. Parts are strings or objects
  # ({ "text" => "...", "wordsOfJesus" => true } or { "noteId" => N } footnote markers).
  def self.verse_text(parts)
    parts.filter_map { |p| p.is_a?(String) ? p : p["text"] }
         .join(" ").gsub("¶", "").gsub(/\s+/, " ").strip
  end

  def self.say(msg)
    Rails.logger.info("[BibleSeeder] #{msg}")
    puts "[BibleSeeder] #{msg}" if $stdout.tty? || Rails.env.local?
  end

  private

  def flush(rows)
    return if rows.empty?
    Verse.upsert_all(rows, unique_by: :index_verses_unique_location)
  end

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
