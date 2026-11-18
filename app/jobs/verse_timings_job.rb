# Works out when each verse starts in a chapter's audio (VerseTimings), once.
class VerseTimingsJob < ApplicationJob
  queue_as :default

  def perform(chapter_audio_id)
    record = ChapterAudio.find_by(id: chapter_audio_id)
    return if record.nil? || record.verse_timings.present? || !record.playable?
    VerseTimings.call(record)
  end
end
