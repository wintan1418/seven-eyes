require "net/http"

# A real person reading the King James Version: the 1999 Audio Scriptures
# International recording (read by Dan Wagner), one mp3 per chapter, hosted on
# archive.org (item "kjvaudio", all 1,189 chapters).
#
# Their terms: free to copy and share, provided it's never sold (we charge
# nothing) and it carries their message, which we show on the Sources & credits
# page. Turn it off with KJV_RECORDING=off.
#
# Each chapter is downloaded once on first play and kept in our own storage,
# so playback never depends on archive.org afterwards.
class KjvRecording
  BASE = "https://archive.org/download/kjvaudio".freeze
  CREDIT = "King James Version read by Dan Wagner, recorded in 1999 by Audio Scriptures International.".freeze
  MESSAGE = "Thank you for listening to this recording of the King James Bible produced by Audio Scriptures " \
            "International. Audio Scriptures International believes it is more important to spread the Word of " \
            "God than to make a large profit. Please feel free to make copies of these recordings and distribute " \
            "them freely so long as you adhere to the following guidelines: 1. You may not charge any more than " \
            "the cost to duplicate and send them. 2. You must make a complete copy of the recording, including " \
            "this message. For commercial and fund raising distribution, please contact Audio Scriptures " \
            "International for additional information.".freeze

  # File prefix per book, in canonical order (Book#position 1..66).
  FILES = [
    "01_Genesis", "02_Exodus", "03_Leviticus", "04_Numbers", "05_Deuteronomy", "06_Joshua", "07_Judges",
    "08_Ruth", "09_1Samuel", "10_2Samuel", "11_1Kings", "12_2Kings", "13_1Chronicles", "14_2Chronicles",
    "15_Ezra", "16_Nehemiah", "17_Esther", "18_Job", "19_Psalms", "20_Proverbs", "21_Ecclesiastes",
    "22_Song_of_Solomon", "23_Isaiah", "24_Jeremiah", "25_Lamentations", "26_Ezekiel", "27_Daniel",
    "28_Hosea", "29_Joel", "30_Amos", "31_Obadiah", "32_Jonah", "33_Micah", "34_Nahum", "35_Habakkuk",
    "36_Zephaniah", "37_Haggai", "38_Zechariah", "39_Malachi", "40_Matthew", "41_Mark", "42_Luke",
    "43_John", "44_Acts", "45_Romans", "46_1Corinthians", "47_2Corinthians", "48_Galatians", "49_Ephesians",
    "50_Philippians", "51_Colossians", "52_1Thessalonians", "53_2Thessalonians", "54_1Timothy", "55_2Timothy",
    "56_Titus", "57_Philemon", "58_Hebrews", "59_James", "60_1Peter", "61_2Peter", "62_1John", "63_2John",
    "64_3John", "65_Jude", "66_Revelation"
  ].freeze

  MAX_BYTES = 15.megabytes

  def self.enabled? = !%w[off false 0 no].include?(ENV["KJV_RECORDING"].to_s.downcase)

  def self.covers?(book, chapter)
    enabled? && FILES[book.position.to_i - 1].present? && chapter.to_i.between?(1, book.chapter_count.to_i)
  end

  def self.url_for(book, chapter)
    prefix = FILES[book.position.to_i - 1] or return
    format("%s/%s_%03d.mp3", BASE, prefix, chapter.to_i)
  end

  def self.call(record) = new(record).call

  def initialize(record)
    @record = record
  end

  # Download the chapter's mp3 and attach it to the record.
  def call
    url = self.class.url_for(@record.book, @record.chapter)
    return fail!(:not_covered) unless url

    audio = fetch(URI(url))
    return fail!(:download) unless audio

    @record.audio.attach(io: StringIO.new(audio), filename: File.basename(url).downcase, content_type: "audio/mpeg")
    @record.update!(status: :ready, error: nil, generated_at: Time.current)
    true
  end

  private

  # archive.org answers /download/ with a redirect to a storage node.
  def fetch(uri, redirects = 4)
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 60) do |http|
      http.request(Net::HTTP::Get.new(uri))
    end
    case res
    when Net::HTTPRedirection
      redirects.positive? ? fetch(URI.join(uri, res["location"]), redirects - 1) : nil
    when Net::HTTPSuccess
      body = res.body.to_s.b
      body if body.bytesize.between?(1, MAX_BYTES)
    end
  rescue => e
    Rails.logger.warn("[KjvRecording] #{e.class}: #{e.message}")
    nil
  end

  def fail!(error)
    @record.update!(status: :failed, error: error.to_s)
    false
  end
end
