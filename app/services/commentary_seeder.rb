require "open-uri"
require "json"

# Seeds public-domain Bible commentary from the HelloAO Free Use Bible API
# (one chapter request per chapter). The running app NEVER calls this API — it is
# a seed-time source only. Idempotent: skips a source whose rows already exist
# unless force: true.
#
#   CommentarySeeder.seed!                       # Matthew Henry (default)
#   CommentarySeeder.seed!(%w[matthew-henry jamieson-fausset-brown])
class CommentarySeeder
  HELLOAO = "https://bible.helloao.org/api".freeze

  SOURCES = {
    "matthew-henry"          => "Matthew Henry",
    "jamieson-fausset-brown" => "Jamieson, Fausset & Brown",
    "adam-clarke"            => "Adam Clarke",
    "john-gill"              => "John Gill",
    "keil-delitzsch"         => "Keil & Delitzsch",
    "tyndale"                => "Tyndale"
  }.freeze

  DEFAULT = %w[matthew-henry].freeze

  def self.seed!(sources = DEFAULT, force: false)
    Array(sources).each { |id| new(id, force:).run }
  end

  def initialize(source, force: false)
    @source = source
    @source_name = SOURCES.fetch(source) { source.titleize }
    @force = force
  end

  def run
    Commentary.where(source: @source).delete_all if @force

    books_by_position = Book.all.index_by(&:position)
    rows = []
    now = Time.current
    total = 0

    book_list.each do |bk|
      book = books_by_position[bk["order"]]
      next unless book

      (1..bk["numberOfChapters"]).each do |chapter|
        # Resumable: skip chapters a previous (interrupted) run already stored.
        next if Commentary.exists?(source: @source, book_id: book.id, chapter:)

        body = chapter_body(bk["id"], chapter)
        next if body.blank?

        rows << {
          source: @source, source_name: @source_name, book_id: book.id,
          chapter:, body:, created_at: now, updated_at: now
        }
        if rows.size >= 40
          flush(rows)
          total += rows.size
          rows = []
        end
      end
    end
    flush(rows)
    total += rows.size
    say "#{@source}: seeded #{total} chapters."
  end

  # Assemble one chapter's commentary into simple, safe HTML paragraphs.
  def chapter_body(book_code, chapter)
    data = fetch_json("#{HELLOAO}/c/#{@source}/#{book_code}/#{chapter}.json")
    content = data.dig("chapter", "content") or return nil

    blocks = content.filter_map do |item|
      paragraphs = Array(item["content"]).flat_map { |s| s.to_s.split(/\n+/) }.map(&:strip).reject(&:blank?)
      next if paragraphs.empty?

      label = item["number"] ? %(<span class="cm-vref">v. #{ERB::Util.html_escape(item['number'])}</span>) : ""
      label + paragraphs.map { |p| "<p>#{ERB::Util.html_escape(p)}</p>" }.join
    end
    blocks.join("\n").presence
  end

  def say(msg)
    Rails.logger.info("[CommentarySeeder] #{msg}")
    puts "[CommentarySeeder] #{msg}" if $stdout.tty? || Rails.env.local?
  end

  private

  def book_list
    fetch_json("#{HELLOAO}/c/#{@source}/books.json")&.fetch("books", []) || []
  end

  def flush(rows)
    return if rows.empty?
    Commentary.upsert_all(rows, unique_by: :index_commentaries_unique)
  end

  def fetch_json(url)
    attempts = 0
    begin
      attempts += 1
      body = URI.parse(url).open(read_timeout: 60, &:read).force_encoding("UTF-8")
      JSON.parse(body)
    rescue OpenURI::HTTPError
      nil # a missing chapter is fine; skip it
    rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError, JSON::ParserError
      # SystemCallError covers all Errno::* network failures (ENETUNREACH, EHOSTUNREACH,
      # ECONNRESET, ECONNREFUSED, ETIMEDOUT, …) — common on a flaky connection.
      if attempts < 8
        sleep([ 2 * attempts, 15 ].min)
        retry
      end
      nil # give up on this chapter; a later run resumes it
    end
  end
end
