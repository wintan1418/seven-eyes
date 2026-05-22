require "open-uri"
require "json"

# Tags KJV verses with Strong's numbers, word by word, sourced once from the
# public-domain bolls.life KJV (which embeds Strong's inline as <S>n</S>). The
# tokens are stored on each verse as JSON: an ordered list of segments, where a
# segment with an "s" key is a clickable word linked to a lexicon entry and a
# segment with only "w" is plain text (spaces, punctuation, untranslated particles).
#
# Old-Testament numbers are Hebrew (H####), New-Testament are Greek (G####).
# Seed-time only; the running app reads tokens from our DB. Idempotent.
class VerseTokenSeeder
  BOLLS = "https://bolls.life/get-text/KJV".freeze

  def self.seed!(force: false)
    new(force:).run
  end

  def initialize(force: false)
    @force = force
  end

  def run
    kjv = Translation.find_by(code: "KJV")
    return say("no KJV translation seeded — run bibles:seed first.") unless kjv

    total = 0
    Book.order(:position).each do |book|
      prefix = book.testament_old? ? "H" : "G"
      (1..book.chapter_count).each do |chapter|
        verses = kjv.verses.where(book:, chapter:).index_by(&:verse_number)
        next if verses.empty?
        # Resumable: a previous (interrupted) run may have tagged this chapter already.
        next if !@force && verses.values.first.tokens.present?

        rows = fetch(book.position, chapter).filter_map do |row|
          verse = verses[row["verse"]]
          next unless verse

          {
            id: verse.id, translation_id: verse.translation_id, book_id: verse.book_id,
            chapter: verse.chapter, verse_number: verse.verse_number, text: verse.text,
            tokens: tokenize(row["text"].to_s, prefix),
            created_at: verse.created_at, updated_at: Time.current
          }
        end
        next if rows.empty?

        Verse.upsert_all(rows, unique_by: :index_verses_unique_location)
        total += rows.size
      end
      say "...#{book.name} done (#{total} verses tagged so far)."
    end
    say "KJV: tagged #{total} verses with Strong's numbers."
  end

  # Turn bolls inline-Strong's text into ordered tokens.
  #   "In the beginning<S>7225</S> God<S>430</S>, <S>853</S> the heaven<S>8064</S>"
  #   => [{w:"In the beginning",s:"H7225"},{w:" God",s:"H430"},{w:", "},{w:" the heaven",s:"H8064"}]
  def tokenize(raw, prefix)
    cleaned = raw.gsub(%r{<(?!/?S>)[^>]*>}, "") # drop non-Strong's tags (italics, footnotes)
    tokens = []
    last = 0
    cleaned.scan(%r{<S>(\d+)</S>}) do
      match = Regexp.last_match
      surface = cleaned[last...match.begin(0)]
      last = match.end(0)
      if surface.strip.empty?
        tokens << { "w" => surface } unless surface.empty?
      else
        tokens << { "w" => surface, "s" => "#{prefix}#{match[1]}" }
      end
    end
    tail = cleaned[last..]
    tokens << { "w" => tail } if tail.present?
    tokens
  end

  def say(msg)
    Rails.logger.info("[VerseTokenSeeder] #{msg}")
    puts "[VerseTokenSeeder] #{msg}" if $stdout.tty? || Rails.env.local?
  end

  private

  def fetch(book_number, chapter)
    attempts = 0
    begin
      attempts += 1
      body = URI.parse("#{BOLLS}/#{book_number}/#{chapter}/").open(read_timeout: 60, &:read).force_encoding("UTF-8")
      JSON.parse(body)
    rescue OpenURI::HTTPError
      []
    rescue SocketError, Socket::ResolutionError, Errno::ECONNRESET, Net::OpenTimeout, Net::ReadTimeout, JSON::ParserError
      if attempts < 8
        sleep([ 2 * attempts, 15 ].min)
        retry
      end
      say "...skipping book #{book_number} ch #{chapter} after #{attempts} failed attempts (will fill on re-run)."
      [] # give up on this chapter; a later run resumes it
    end
  end
end
