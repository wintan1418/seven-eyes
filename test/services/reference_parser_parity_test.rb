require "test_helper"
require "open3"

# The offline reader parses references in the browser / service worker with a
# JavaScript port of ReferenceParser (app/javascript/lib/offline/reference_parser.js).
# A typed reference must mean the same thing online and offline, so this runs
# both parsers over the same inputs — every input the Ruby parser's own tests
# use plus a sweep of awkward ones — and compares the results field by field.
class ReferenceParserParityTest < ActiveSupport::TestCase
  RUNNER = Rails.root.join("test/javascript/reference_parser_runner.mjs")

  EXTRA_INPUTS = [
    "Jn 3:16", "jn 3", "John 3:16-18", "1 Cor 1:1", "1cor1:1", "Song 2:1", "Psalm 23", "Ps 23",
    "romans 5:1", "", "   ", "nonsense", "John 99", "John 0", "John 3:0", "Jude 3", "Jude 1-3", "jude 3-1",
    "Philippians", "phillipians 4", "mathew 5", "duet 6:4", "thes 4", "1 thes 4:16", "First John 1:9",
    "II Kings 2", "iii john 4", "St John 3:16", "John chapter 3 verse 16", "John 3 v 16", "Gen. 1:1",
    "jeremiah:29:11", "John 3:16ff", "John 3:16f", "John 3:16a", "John 3:16b-18", "John 3:18-16",
    "John 3:16–4:2", "John 3:16-4:2", "Matt 5-7", "Matt 7-5", "Matt 5-29", "John 3:16-2:1",
    "Rev 22:21", "rev 23", "Obad 1", "Obad 21", "Phlm 1:25", "3 John 14", "song of songs 2",
    "song of solomon 2:1", "canticles 1", "Psalms 119:105", "psa 23:1-6", "pss 1", "Ecc 3:1-8",
    "ez 37", "eze 37:1-14", "jn3:16", "JN 3 16", "John 3,16", "John 3.16", "1 Corinthians 13",
    "1co 13:4-7", "Heb 11", "hebrewz 11", "Acts 2:1-4;", "(Rom 8:28)", "\"Rom 8:28\"", "Rom 8:28!",
    "Isaiah 53:5,", "Is 40:31", "lam 3:22-23", "joel 2:28", "am 5:24", "mic 6:8", "hab 2:4",
    "zeph 3:17", "hag 2:9", "zech 4:6", "mal 3:10", "mark 16:15", "luke 15", "ga 5:22", "eph 6:10-18",
    "col 3", "1 tim 4:12", "2 tim 3:16-17", "titus 2", "jas 1:2-4", "1 pet 5:7", "2 pet 3:9",
    "1 john 4:8", "2 jn 6", "Revelation 21:1-4", "gen", "g", "ge", "jo 3", "1 sam 17", "2sam 7"
  ].freeze

  setup do
    skip "node is not installed" unless system("node", "--version", out: File::NULL, err: File::NULL)
  end

  test "the JavaScript parser reads every reference exactly like ReferenceParser" do
    inputs = (ruby_test_inputs + EXTRA_INPUTS).uniq
    canon = Bible::Canon.all.map { |b| { osis: b.osis, name: b.name, chapters: b.chapter_count, aliases: b.aliases } }
    out, err, status = Open3.capture3("node", RUNNER.to_s, stdin_data: { canon:, inputs: }.to_json)
    assert status.success?, "node runner failed: #{err}"

    JSON.parse(out).zip(inputs).each do |js, input|
      assert_equal expected(ReferenceParser.call(input)), js, "parsers disagree on #{input.inspect}"
    end
  end

  private

  def expected(r)
    return { "valid" => false, "error" => r.error.to_s, "osis" => r.osis } unless r.valid?

    { "valid" => true, "osis" => r.osis, "chapter" => r.chapter, "chapter_end" => r.chapter_end,
      "verse_start" => r.verse_start, "verse_end" => r.verse_end, "open_ended" => r.open_ended?,
      "label" => r.label }
  end

  # Every literal the Ruby parser's own tests feed it.
  def ruby_test_inputs
    Rails.root.join("test/services/reference_parser_test.rb").read
         .scan(/parse\("((?:[^"\\]|\\.)*)"\)/).flatten.map { |s| s.gsub('\"', '"') }
  end
end
