# The Audio Bible endpoint: the reader asks for a chapter's narration and gets
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
    return render json: { ok: false, status: "unavailable" } unless OpenaiSpeech.configured?

    record = ChapterAudio.find_by(translation:, book:, chapter:, voice: OpenaiSpeech.voice)
    return request_generation(translation, book, chapter) if record.nil?

    if record.playable?
      render json: payload(book, chapter, translation, "ready",
                           url: rails_storage_proxy_path(record.audio))
    elsif record.failed?
      retry_failed(record, book, chapter, translation)
    else
      requeue_if_stale(record)
      render json: payload(book, chapter, translation, "preparing")
    end
  end

  private

  def daily_cap = (ENV["AUDIO_DAILY_CAP"].presence || DAILY_CAP).to_i

  def request_generation(translation, book, chapter)
    if ChapterAudio.requested_today.count >= daily_cap
      return render json: { ok: false, status: "quota" }
    end
    record = ChapterAudio.create!(translation:, book:, chapter:, voice: OpenaiSpeech.voice)
    ChapterAudioJob.perform_later(record.id)
    render json: payload(book, chapter, translation, "preparing")
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # Two listeners raced — the other one's record wins.
    render json: payload(book, chapter, translation, "preparing")
  end

  def retry_failed(record, book, chapter, translation)
    if record.updated_at < RETRY_FAILED.ago
      record.update!(status: :pending, error: nil)
      ChapterAudioJob.perform_later(record.id)
      render json: payload(book, chapter, translation, "preparing")
    else
      render json: { ok: false, status: "failed" }
    end
  end

  # The async adapter loses queued jobs on restart; touch so each poll cycle
  # only requeues once per staleness window.
  def requeue_if_stale(record)
    return unless record.updated_at < STALE_PENDING.ago
    record.touch
    ChapterAudioJob.perform_later(record.id)
  end

  def payload(book, chapter, translation, status, url: nil)
    nxt = next_chapter(book, chapter)
    {
      ok: true, status:, url:,
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
