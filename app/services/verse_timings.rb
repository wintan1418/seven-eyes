require "net/http"

# The second each verse starts in a narrated chapter, so the reader can light
# the verse being read and scroll exactly with the voice (human reader or AI).
#
# The audio is transcribed once with word timestamps (OpenAI speech-to-text,
# about $0.006 a minute: ~3 cents a chapter, cached forever), then each verse's
# opening words are found in the transcript in order. Verses that can't be
# matched are placed between their neighbours by length.
class VerseTimings
  URL = URI("https://api.openai.com/v1/audio/transcriptions").freeze
  LOOKAHEAD = 4 # opening words compared per verse

  def self.configured? = OpenaiSpeech.configured?

  def self.call(chapter_audio) = new(chapter_audio).call

  def initialize(chapter_audio)
    @record = chapter_audio
  end

  # Saves { verse_number => start_seconds } on the record; returns it (or nil).
  def call
    @record.update_columns(timings_attempted_at: Time.current)
    return unless self.class.configured? && @record.playable?
    words = @record.audio.open { |file| transcribe(file) }
    return if words.blank?
    timings = self.class.align(verses.map { |v| [ v.verse_number, v.text.to_s ] }, words)
    @record.update_columns(verse_timings: timings) if timings.present?
    timings
  rescue => e
    Rails.logger.warn("[VerseTimings] #{@record.id}: #{e.class}: #{e.message}")
    nil
  end

  # verses: [[number, text], ...]; words: [{ "word" =>, "start" => }, ...]
  def self.align(verses, words)
    said = words.map { |w| [ norm(w["word"]), w["start"].to_f ] }.reject { |t, _| t.empty? }
    return {} if said.empty? || verses.empty?

    starts = Array.new(verses.size)
    pointer = 0
    verses.each_with_index do |(_, text), i|
      tokens = text.split.map { |t| norm(t) }.reject(&:empty?)
      next if tokens.empty?
      head = tokens.first(LOOKAHEAD)
      window_end = [ said.size - 1, pointer + tokens.size * 3 + 40 ].min
      best, best_score = nil, 0
      (pointer..window_end).each do |j|
        score = head.each_with_index.count { |tok, k| said[j + k]&.first == tok }
        if score > best_score
          best, best_score = j, score
          break if score == head.size
        end
      end
      needed = head.size >= 3 ? 2 : 1
      next unless best && best_score >= needed
      starts[i] = said[best].last
      pointer = best + [ (tokens.size * 0.6).floor, 1 ].max
    end

    fill_gaps(verses, starts, said.last.last)
    verses.each_with_index.to_h { |(number, _), i| [ number.to_s, starts[i]&.round(2) ] }.compact
  end

  # Unmatched verses sit between their matched neighbours, spaced by length.
  def self.fill_gaps(verses, starts, end_time)
    lengths = verses.map { |_, t| t.length + 12 }
    i = 0
    while i < starts.size
      if starts[i]
        i += 1
        next
      end
      j = i
      j += 1 while j < starts.size && starts[j].nil?
      from = i.zero? ? (starts[j] ? [ starts[j] - lengths[i...j].sum * 0.06, 0 ].max : 0) : starts[i - 1]
      to = j < starts.size ? starts[j] : end_time
      span_lengths = ((i.zero? ? i : i - 1)...j).map { |k| lengths[k] }
      total = span_lengths.sum.to_f
      acc = i.zero? ? 0 : lengths[i - 1]
      (i...j).each do |k|
        starts[k] = i.zero? && k == i ? from : from + (to - from) * (acc / total)
        acc += lengths[k]
      end
      i = j
    end
  end

  def self.norm(word) = word.to_s.downcase.gsub(/[^a-z0-9]/, "")

  private

  def verses
    Verse.where(translation_id: @record.translation_id, book_id: @record.book_id, chapter: @record.chapter)
         .order(:verse_number)
  end

  def transcribe(file)
    req = Net::HTTP::Post.new(URL)
    req["Authorization"] = "Bearer #{OpenaiSpeech.new('').send(:api_key)}"
    req.set_form([
      [ "file", file, { filename: "chapter.mp3", content_type: "audio/mpeg" } ],
      [ "model", "whisper-1" ],
      [ "response_format", "verbose_json" ],
      [ "timestamp_granularities[]", "word" ],
      [ "language", "en" ]
    ], "multipart/form-data")
    res = Net::HTTP.start(URL.host, 443, use_ssl: true, read_timeout: 300, open_timeout: 15) { |h| h.request(req) }
    raise "HTTP #{res.code}: #{res.body.to_s[0, 160]}" unless res.is_a?(Net::HTTPSuccess)
    JSON.parse(res.body)["words"]
  end
end
