require "open-uri"
require "json"

# Seeds Strong's Greek + Hebrew lexicon entries from the public-domain
# openscriptures dictionaries (CC-BY-SA, derived from Strong's 1890/1894).
# One-time seed source; the running app reads only from our DB. Idempotent.
class LexiconSeeder
  SOURCES = {
    "greek"  => "https://raw.githubusercontent.com/openscriptures/strongs/master/greek/strongs-greek-dictionary.js",
    "hebrew" => "https://raw.githubusercontent.com/openscriptures/strongs/master/hebrew/strongs-hebrew-dictionary.js"
  }.freeze

  def self.seed!(force: false)
    SOURCES.each { |language, url| new(language, url, force:).run }
  end

  def initialize(language, url, force: false)
    @language = language
    @url = url
    @force = force
  end

  def run
    if !@force && LexiconEntry.where(language: @language).exists?
      say "#{@language}: already seeded (#{LexiconEntry.where(language: @language).count}) — skipping."
      return
    end

    dict = parse(download)
    now = Time.current
    rows = dict.map do |strongs, e|
      {
        strongs: strongs.upcase, language: @language,
        lemma: e["lemma"],
        # Greek entries use "translit"; Hebrew entries use "xlit" (fallback to "pron").
        translit: (e["translit"] || e["xlit"] || e["pron"])&.strip,
        definition: e["strongs_def"]&.strip, kjv_def: e["kjv_def"]&.strip,
        derivation: e["derivation"]&.strip,
        created_at: now, updated_at: now
      }
    end
    rows.each_slice(2_000) { |slice| LexiconEntry.upsert_all(slice, unique_by: :strongs) }
    say "#{@language}: seeded #{rows.size} entries."
  end

  # The dictionaries are JS files that assign one big JSON object. Extract the
  # object literal (from the first "{...}" containing entries to its matching
  # closing brace) and parse it as JSON.
  def parse(body)
    start = body.index(/\{\s*"[GH]\d/)
    raise "lexicon object not found" unless start

    json = body[start..body.rindex("}")]
    JSON.parse(json)
  end

  def say(msg)
    Rails.logger.info("[LexiconSeeder] #{msg}")
    puts "[LexiconSeeder] #{msg}" if $stdout.tty? || Rails.env.local?
  end

  private

  def download
    attempts = 0
    begin
      attempts += 1
      URI.parse(@url).open(read_timeout: 60, &:read).force_encoding("UTF-8")
    rescue SocketError, Socket::ResolutionError, Errno::ECONNRESET, Net::OpenTimeout, Net::ReadTimeout, OpenURI::HTTPError
      raise if attempts >= 8
      sleep([ 2 * attempts, 15 ].min)
      retry
    end
  end
end
