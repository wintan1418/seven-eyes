# Root word projection: Strong's pronunciation (Hebrew "pron", e.g. "baw-raw'",
# marks the stressed syllable for the say-it guide) and the word study a live
# session's phones show while it is on the big screen.
class AddRootWords < ActiveRecord::Migration[8.1]
  def change
    add_column :lexicon_entries, :pron, :string
    add_column :live_sessions, :slide_word, :jsonb
  end
end
