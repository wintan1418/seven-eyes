# Prepares one chapter's audio in the background (production uses the
# async adapter, so this runs in-process — the request never waits on TTS).
class ChapterAudioJob < ApplicationJob
  queue_as :default

  def perform(chapter_audio_id)
    record = ChapterAudio.find_by(id: chapter_audio_id)
    return if record.nil? || record.playable?

    if record.voice == AudioVoices::HUMAN.id
      KjvRecording.call(record) # a real reader's recording, fetched once
    else
      ChapterNarration.call(record) # Google or OpenAI text-to-speech
    end
  end
end
