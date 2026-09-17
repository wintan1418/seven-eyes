# Narrate one chapter into a cached mp3 on a ChapterAudio record: build the
# spoken text (a short heading, then every verse — no verse numbers, they read
# terribly aloud), chunk it under the TTS input cap at verse boundaries,
# synthesize each chunk, and attach the concatenated audio. Sequentially
# encoded mp3 segments concatenate cleanly, so no transcoding is needed.
class ChapterNarration
  MAX_CHUNK = 3800 # comfortably under OpenaiSpeech::MAX_INPUT

  def self.call(chapter_audio) = new(chapter_audio).call

  def initialize(chapter_audio)
    @record = chapter_audio
  end

  def call
    verses = Verse.where(translation: @record.translation, book: @record.book,
                         chapter: @record.chapter).order(:verse_number)
    return fail!(:no_verses) if verses.empty?

    audio = "".b
    chunk_texts(verses).each do |text|
      result = synthesize(text)
      return fail!(result.error || :api) unless result.ok?
      audio << result.audio
    end

    @record.audio.attach(io: StringIO.new(audio), filename: filename, content_type: "audio/mpeg")
    @record.update!(status: :ready, error: nil, generated_at: Time.current)
    true
  end

  private

  # Seam for tests (mirrors FakeRabbi / FakeChapterPrayer).
  def synthesize(text) = OpenaiSpeech.synthesize(text)

  def heading
    "#{@record.book.name}, chapter #{@record.chapter}. #{@record.translation.name}."
  end

  def chunk_texts(verses)
    chunks = [ heading.dup ]
    verses.each do |verse|
      text = verse.text.to_s.strip
      next if text.empty?
      if chunks.last.length + text.length + 1 > MAX_CHUNK
        chunks << text.dup
      else
        chunks.last << " " << text
      end
    end
    chunks
  end

  def filename
    "#{@record.translation.code}-#{@record.book.osis_code}-#{@record.chapter}.mp3".downcase
  end

  def fail!(error)
    @record.update!(status: :failed, error: error.to_s)
    false
  end
end
