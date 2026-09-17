require "test_helper"

class AudioChaptersTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    Verse.create!(translation: @kjv, book: @john, chapter: 3, verse_number: 16,
                  text: "For God so loved the world")
  end

  # OpenaiSpeech.configured? reads only these ENV keys in test (credentials are
  # empty there), so setting/clearing them controls the endpoint's key check.
  TTS_KEYS = %w[OPENAI_API_KEY OPENAI_KEY].freeze

  def with_tts_key(present)
    saved = TTS_KEYS.index_with { |k| ENV[k] }
    TTS_KEYS.each { |k| ENV.delete(k) }
    ENV["OPENAI_API_KEY"] = "test-key" if present
    yield
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  def request_chapter(osis: "John", chapter: 3, translation: "KJV")
    get audio_chapter_path, params: { osis:, chapter:, translation: }
    response.parsed_body
  end

  test "an unknown translation, book or chapter is a 404" do
    with_tts_key(true) do
      get audio_chapter_path, params: { osis: "John", chapter: 3, translation: "NOPE" }
      assert_response :not_found
      get audio_chapter_path, params: { osis: "Nope", chapter: 3, translation: "KJV" }
      assert_response :not_found
      get audio_chapter_path, params: { osis: "John", chapter: 99, translation: "KJV" }
      assert_response :not_found
    end
  end

  test "reports unavailable when no TTS key is configured" do
    with_tts_key(false) do
      body = request_chapter
      assert_response :success
      assert_equal "unavailable", body["status"]
    end
  end

  test "first request creates the record, enqueues generation and reports preparing" do
    with_tts_key(true) do
      body = nil
      assert_difference -> { ChapterAudio.count }, 1 do
        assert_enqueued_with(job: ChapterAudioJob) { body = request_chapter }
      end
      assert_equal "preparing", body["status"]
      assert_equal "John 3", body["title"]
      assert_equal({ "osis" => "John", "chapter" => 4, "translation" => "KJV" }, body["next"])
      assert ChapterAudio.exists?(translation: @kjv, book: @john, chapter: 3, status: :pending)
    end
  end

  test "a ready chapter returns its permanent proxy URL" do
    record = ChapterAudio.create!(translation: @kjv, book: @john, chapter: 3,
                                  voice: OpenaiSpeech.voice, status: :ready)
    record.audio.attach(io: StringIO.new("mp3bytes"), filename: "a.mp3", content_type: "audio/mpeg")

    with_tts_key(true) do
      body = request_chapter
      assert_equal "ready", body["status"]
      assert_match %r{/rails/active_storage/}, body["url"]
      assert_equal "King James Version", body["translation_name"]
    end
  end

  test "the last chapter of the canon has no next" do
    rev = Book.create!(osis_code: "Rev", name: "Revelation", testament: :new,
                       position: 66, chapter_count: 22)
    Verse.create!(translation: @kjv, book: rev, chapter: 22, verse_number: 1, text: "And he shewed me")
    with_tts_key(true) do
      body = request_chapter(osis: "Rev", chapter: 22)
      assert_nil body["next"]
    end
  end

  test "next wraps across a book boundary" do
    acts = Book.create!(osis_code: "Acts", name: "Acts", testament: :new,
                        position: 44, chapter_count: 28)
    with_tts_key(true) do
      body = request_chapter(osis: "John", chapter: 21)
      assert_equal({ "osis" => acts.osis_code, "chapter" => 1, "translation" => "KJV" }, body["next"])
    end
  end

  test "a stale pending record is requeued once per staleness window" do
    record = ChapterAudio.create!(translation: @kjv, book: @john, chapter: 3, voice: OpenaiSpeech.voice)
    record.update_columns(updated_at: 10.minutes.ago)

    with_tts_key(true) do
      assert_enqueued_with(job: ChapterAudioJob) { request_chapter }
      # Touched — polling again immediately does not requeue a second time.
      assert_no_enqueued_jobs(only: ChapterAudioJob) { request_chapter }
    end
  end

  test "a fresh failure reports failed; an old one retries" do
    record = ChapterAudio.create!(translation: @kjv, book: @john, chapter: 3,
                                  voice: OpenaiSpeech.voice, status: :failed, error: "api")
    with_tts_key(true) do
      assert_equal "failed", request_chapter["status"]

      record.update_columns(updated_at: 1.hour.ago)
      body = nil
      assert_enqueued_with(job: ChapterAudioJob) { body = request_chapter }
      assert_equal "preparing", body["status"]
      assert record.reload.pending?
    end
  end

  test "the global daily cap halts new generations but still serves cached audio" do
    cap = AudioChaptersController::DAILY_CAP
    now = Time.current
    ChapterAudio.insert_all((1..cap).map { |i|
      { translation_id: @kjv.id, book_id: @john.id, chapter: 100 + i, voice: "x",
        status: 0, created_at: now, updated_at: now }
    })

    with_tts_key(true) do
      body = request_chapter
      assert_equal "quota", body["status"]

      record = ChapterAudio.create!(translation: @kjv, book: @john, chapter: 3,
                                    voice: OpenaiSpeech.voice, status: :ready)
      record.audio.attach(io: StringIO.new("mp3"), filename: "a.mp3", content_type: "audio/mpeg")
      assert_equal "ready", request_chapter["status"]
    end
  end

  test "the endpoint is open to guests" do
    with_tts_key(false) do
      get audio_chapter_path, params: { osis: "John", chapter: 3, translation: "KJV" }
      assert_response :success
    end
  end
end
