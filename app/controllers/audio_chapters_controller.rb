# The Audio Bible endpoint: the reader asks for a chapter's narration (in a
# chosen voice, or "auto" — see AudioVoices for the order) and gets
# JSON — ready (with a permanent proxy URL), preparing (generation enqueued;
# poll again), or a reason to fall back to on-device speech synthesis. Audio is
# generated once per translation+chapter+voice and cached forever; a global
# daily cap on NEW generations bounds the TTS bill against scripted abuse.
class AudioChaptersController < ApplicationController
  allow_unauthenticated_access

  DAILY_CAP = 250          # new chapter generations per day, across everyone (AUDIO_DAILY_CAP)
  STALE_PENDING = 5.minutes  # a pending job older than this likely died — requeue
  RETRY_FAILED = 10.minutes  # let failures rest before trying again

  def show
    translation = Translation.find_by(code: params[:translation].to_s)
    book = Book.find_by_osis(params[:osis].to_s)
    chapter = params[:chapter].to_i
    unless translation && book && chapter.between?(1, book.chapter_count)
      return render json: { ok: false, status: "unknown" }, status: :not_found
    end

    voices = AudioVoices.chain(params[:voice], translation:, book:, chapter:)
    return render json: { ok: false, status: "unavailable" } if voices.empty?

    # Best voice first; a voice that recently failed or is over its cap hands
    # over to the next one, so a listener is never stuck on a broken provider.
    outcome = "failed"
    voices.each do |voice|
      record = ChapterAudio.find_by(translation:, book:, chapter:, voice: voice.id)

      if record.nil?
        if voice.paid? && over_daily_cap?
          outcome = "quota"
          next
        end
        return request_generation(translation, book, chapter, voice)
      elsif record.playable?
        return render json: payload(book, chapter, translation, "ready", voice,
                                    url: rails_storage_proxy_path(record.audio))
      elsif record.failed?
        next unless record.updated_at < RETRY_FAILED.ago
        record.update!(status: :pending, error: nil)
        ChapterAudioJob.perform_later(record.id)
        return render json: payload(book, chapter, translation, "preparing", voice)
      else
        requeue_if_stale(record)
        return render json: payload(book, chapter, translation, "preparing", voice)
      end
    end
    render json: { ok: false, status: outcome }
  end

  SAMPLE_TEXT = "The Lord is my shepherd; I shall not want. He maketh me to lie down in green pastures."

  # A few seconds of a voice, for the chooser's preview button. Made once per
  # voice and cached, so previews cost (almost) nothing.
  def sample
    voice = AudioVoices.find(params[:voice])
    return head :not_found unless voice&.server?

    if voice.provider == :recording
      book = Book.find_by(position: 19) # Psalm 23
      return head :not_found unless book && KjvRecording.covers?(book, 23)
      return redirect_to KjvRecording.url_for(book, 23), allow_other_host: true
    end

    audio = Rails.cache.fetch("audio_sample/v1/#{voice.id}", expires_in: 1.year, skip_nil: true) do
      result = case voice.provider
      when :google
        GoogleSpeech.synthesize(SAMPLE_TEXT, voice: voice.provider_voice, language: voice.language) if GoogleSpeech.configured?
      when :openai
        OpenaiSpeech.synthesize(SAMPLE_TEXT, voice: voice.provider_voice) if OpenaiSpeech.configured?
      end
      result&.ok? ? result.audio : nil
    end
    return head :service_unavailable unless audio

    expires_in 1.week, public: true
    send_data audio, type: "audio/mpeg", disposition: "inline"
  end

  private

  def daily_cap = (ENV["AUDIO_DAILY_CAP"].presence || DAILY_CAP).to_i

  # The cap is on paid narration; free recordings and Google's free
  # allowance don't count toward it.
  def over_daily_cap?
    paid = AudioVoices::OPENAI.map(&:id) + [ "x" ]
    ChapterAudio.requested_today.where(voice: paid).count >= daily_cap
  end

  def request_generation(translation, book, chapter, voice)
    record = ChapterAudio.create!(translation:, book:, chapter:, voice: voice.id)
    ChapterAudioJob.perform_later(record.id)
    render json: payload(book, chapter, translation, "preparing", voice)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # Two listeners raced — the other one's record wins.
    render json: payload(book, chapter, translation, "preparing", voice)
  end

  # The async adapter loses queued jobs on restart; touch so each poll cycle
  # only requeues once per staleness window.
  def requeue_if_stale(record)
    return unless record.updated_at < STALE_PENDING.ago
    record.touch
    ChapterAudioJob.perform_later(record.id)
  end

  def payload(book, chapter, translation, status, voice, url: nil)
    nxt = next_chapter(book, chapter)
    {
      ok: true, status:, url:,
      voice: voice.id, voice_name: voice.name,
      title: "#{book.name} #{chapter}",
      book: book.name, chapter:, translation: translation.code,
      translation_name: translation.name,
      next: nxt && { osis: nxt[0].osis_code, chapter: nxt[1], translation: translation.code }
    }
  end

  # Next chapter, wrapping at book boundaries (Genesis 50 → Exodus 1), so a
  # listener with the screen off flows straight through the canon.
  def next_chapter(book, chapter)
    return [ book, chapter + 1 ] if chapter < book.chapter_count
    nxt = Book.where("position > ?", book.position).order(:position).first
    nxt && [ nxt, 1 ]
  end
end
