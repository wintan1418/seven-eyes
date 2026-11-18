# When each verse starts in a chapter's audio ({ "1" => 4.9, "2" => 21.3, ... }),
# so the reader highlights and scrolls exactly with the voice. nil = not made yet.
class AddVerseTimingsToChapterAudios < ActiveRecord::Migration[8.1]
  def change
    add_column :chapter_audios, :verse_timings, :jsonb
    add_column :chapter_audios, :timings_attempted_at, :datetime
  end
end
