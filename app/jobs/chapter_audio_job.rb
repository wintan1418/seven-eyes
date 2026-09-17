# Generates one chapter's narration in the background (production uses the
# async adapter, so this runs in-process — the request never waits on TTS).
class ChapterAudioJob < ApplicationJob
  queue_as :default

  def perform(chapter_audio_id)
    record = ChapterAudio.find_by(id: chapter_audio_id)
    return if record.nil? || record.playable?
    ChapterNarration.call(record)
  end
end
