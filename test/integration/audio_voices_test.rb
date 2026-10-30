require "test_helper"

# The Audio Bible's voice order: a human KJV recording first, then Google's
# free allowance, then OpenAI, then the phone's voice — or a chosen voice
# first, with the rest following if it can't play.
class AudioVoicesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  ENV_KEYS = %w[KJV_RECORDING GOOGLE_TTS_API_KEY OPENAI_API_KEY OPENAI_KEY].freeze

  setup do
    @saved_env = ENV_KEYS.index_with { |k| ENV[k] }
    ENV_KEYS.each { |k| ENV.delete(k) }
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @web = Translation.create!(code: "WEB", name: "World English Bible")
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
  end

  teardown do
    @saved_env.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  # Temporarily replace a class method (minitest 6 has no built-in stubs).
  def swap(klass, name, impl)
    original = klass.method(name)
    klass.define_singleton_method(name, impl)
    yield
  ensure
    klass.define_singleton_method(name, original)
  end

  def keys(google: false, openai: false)
    ENV["GOOGLE_TTS_API_KEY"] = "g-test" if google
    ENV["OPENAI_API_KEY"] = "o-test" if openai
  end

  def request_chapter(translation: "KJV", voice: nil)
    get audio_chapter_path, params: { osis: "John", chapter: 3, translation:, voice: }.compact
    response.parsed_body
  end

  test "KJV starts with the human reader, with no keys at all" do
    body = nil
    assert_enqueued_with(job: ChapterAudioJob) { body = request_chapter }
    assert_equal "preparing", body["status"]
    assert_equal "human", body["voice"]
    assert_equal "Human reader", body["voice_name"]
  end

  test "other translations skip the human reader: Google, then OpenAI" do
    assert_equal "unavailable", request_chapter(translation: "WEB")["status"]

    keys(google: true, openai: true)
    assert_equal "google:en-GB-Neural2-B", request_chapter(translation: "WEB")["voice"]
  end

  test "a failed voice hands over to the next one" do
    keys(google: true, openai: true)
    ChapterAudio.create!(translation: @kjv, book: @john, chapter: 3, voice: "human", status: :failed, error: "download")
    assert_equal "google:en-GB-Neural2-B", request_chapter["voice"]

    ChapterAudio.find_by(voice: "google:en-GB-Neural2-B").update!(status: :failed, error: "api")
    assert_equal "onyx", request_chapter["voice"]
  end

  test "a chosen voice comes first" do
    keys(google: true, openai: true)
    assert_equal "nova", request_chapter(voice: "nova")["voice"]
    assert_equal "google:en-US-Neural2-F", request_chapter(translation: "WEB", voice: "google:en-US-Neural2-F")["voice"]
  end

  test "an unknown voice behaves like auto, and the phone voice skips the server" do
    assert_equal "human", request_chapter(voice: "nonsense")["voice"]
    assert_equal "unavailable", request_chapter(voice: "device")["status"]
  end

  test "KJV_RECORDING=off turns the human reader off" do
    ENV["KJV_RECORDING"] = "off"
    keys(openai: true)
    assert_equal "onyx", request_chapter["voice"]
  end

  test "the job fetches the recording for the human reader" do
    record = ChapterAudio.create!(translation: @kjv, book: @john, chapter: 3, voice: "human")
    called = nil
    swap(KjvRecording, :call, ->(r) { called = r }) do
      swap(ChapterNarration, :call, ->(_) { flunk "should not narrate" }) do
        ChapterAudioJob.perform_now(record.id)
      end
    end
    assert_equal record, called
  end

  test "recording URLs follow the archive's per-chapter files" do
    assert_equal "https://archive.org/download/kjvaudio/43_John_003.mp3", KjvRecording.url_for(@john, 3)
    psalms = Book.create!(osis_code: "Ps", name: "Psalms", testament: :old, position: 19, chapter_count: 150)
    assert_equal "https://archive.org/download/kjvaudio/19_Psalms_119.mp3", KjvRecording.url_for(psalms, 119)
    assert_equal 66, KjvRecording::FILES.size
  end

  test "the human reader's preview is Psalm 23 from the recording" do
    Book.create!(osis_code: "Ps", name: "Psalms", testament: :old, position: 19, chapter_count: 150)
    get audio_sample_path, params: { voice: "human" }
    assert_redirected_to "https://archive.org/download/kjvaudio/19_Psalms_023.mp3"

    get audio_sample_path, params: { voice: "device" }
    assert_response :not_found
  end

  test "the reading settings list the voices this server can use" do
    keys(google: true)
    voices = AudioVoices.selectable.map(&:id)
    assert_includes voices, "human"
    assert_includes voices, "google:en-GB-Neural2-B"
    assert_not_includes voices, "onyx"
    assert_equal "device", voices.last
  end

  test "the reading page has the voice chooser with Auto, previews and the phone voice" do
    keys(google: true)
    user = users(:one)
    study = user.studies.create!(name: "Voices", pane_count: 1)
    sign_in_as user

    get study_path(study)

    assert_select "[data-controller~='voice-choice'][data-voice-choice-sample-url-value='#{audio_sample_path}']" do
      assert_select ".ui-voice[data-voice-id='auto'] .ui-voice-name", text: "Auto"
      assert_select ".ui-voice[data-voice-id='human'] .ui-voice-tag", text: "KJV"
      assert_select ".ui-voice[data-voice-id='google:en-GB-Neural2-B'] button[data-action='voice-choice#preview']"
      assert_select ".ui-voice[data-voice-id='device']"
      assert_select ".ui-voice[data-voice-id='onyx']", count: 0 # no OpenAI key here
    end
  end
end
