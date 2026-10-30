require "test_helper"

class ChapterNarrationTest < ActiveSupport::TestCase
  # Subclass seam: override the network call (mirrors FakeChapterPrayer).
  class FakeNarration < ChapterNarration
    attr_reader :inputs
    def initialize(record, results: nil)
      super(record)
      @inputs = []
      @results = results
    end

    def synthesize(text)
      @inputs << text
      @results ? @results.shift : OpenaiSpeech::Result.new(ok: true, audio: "CHUNK#{@inputs.size}".b)
    end
  end

  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    @record = ChapterAudio.create!(translation: @kjv, book: @john, chapter: 3, voice: "onyx")
  end

  # Temporarily replace a class method (minitest 6 has no built-in stubs).
  def swap(klass, name, impl)
    original = klass.method(name)
    klass.define_singleton_method(name, impl)
    yield
  ensure
    klass.define_singleton_method(name, original)
  end

  def add_verse(num, text)
    Verse.create!(translation: @kjv, book: @john, chapter: 3, verse_number: num, text: text)
  end

  test "narrates the heading plus every verse and attaches the concatenated mp3" do
    add_verse(16, "For God so loved the world")
    add_verse(17, "For God sent not his Son to condemn")

    assert FakeNarration.new(@record).call
    assert @record.reload.ready?
    assert @record.audio.attached?
    assert_equal "kjv-john-3.mp3", @record.audio.filename.to_s
    assert_equal "CHUNK1", @record.audio.download
    assert @record.generated_at.present?
  end

  test "speaks a heading first, then the verses without verse numbers" do
    add_verse(16, "For God so loved the world")
    svc = FakeNarration.new(@record)
    svc.call
    assert_equal 1, svc.inputs.size
    assert_match(/\AJohn, chapter 3\. King James Version\. For God so loved/, svc.inputs.first)
    refute_match(/16/, svc.inputs.first)
  end

  test "splits long chapters into chunks at verse boundaries" do
    add_verse(1, "a" * 2000)
    add_verse(2, "b" * 2000)
    add_verse(3, "c" * 2000)

    svc = FakeNarration.new(@record)
    assert svc.call
    assert_equal 3, svc.inputs.size # heading+v1 | v2 | v3 — each under MAX_CHUNK
    assert svc.inputs.all? { |t| t.length <= ChapterNarration::MAX_CHUNK }
    assert_equal "CHUNK1CHUNK2CHUNK3", @record.reload.audio.download
  end

  test "a failed synthesis marks the record failed with the error, nothing attached" do
    add_verse(16, "For God so loved the world")
    svc = FakeNarration.new(@record, results: [ OpenaiSpeech::Result.new(ok: false, error: :api) ])
    refute svc.call
    assert @record.reload.failed?
    assert_equal "api", @record.error
    refute @record.audio.attached?
  end

  test "a chapter with no verses fails cleanly" do
    refute FakeNarration.new(@record).call
    assert @record.reload.failed?
    assert_equal "no_verses", @record.error
  end

  test "a Google voice is read by Google; filenames name non-default voices" do
    record = ChapterAudio.create!(translation: @kjv, book: @john, chapter: 4, voice: "google:en-GB-Neural2-B")
    Verse.create!(translation: @kjv, book: @john, chapter: 4, verse_number: 1, text: "When therefore the Lord knew")
    calls = []
    fake = ->(text, voice:, language:) { calls << [ voice, language ]; OpenaiSpeech::Result.new(ok: true, audio: "G".b) }
    swap(GoogleSpeech, :synthesize, fake) do
      assert ChapterNarration.call(record)
    end
    assert_equal [ [ "en-GB-Neural2-B", "en-GB" ] ], calls
    assert_equal "kjv-john-4-en-gb-neural2-b.mp3", record.reload.audio.filename.to_s
  end
end
