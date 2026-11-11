# "Word for Today": one Scripture passage per calendar day (Africa/Lagos) with a
# short AI reflection and prayer. The verse text is snapshotted so a day's word
# reads the same forever, even if a translation is re-seeded.
class CreateDailyWords < ActiveRecord::Migration[8.1]
  def change
    create_table :daily_words do |t|
      t.date :date, null: false
      t.string :reference, null: false
      t.string :osis_code, null: false
      t.integer :chapter, null: false
      t.integer :verse_start, null: false
      t.integer :verse_end, null: false
      t.string :translation_code, null: false
      t.text :verse_text, null: false
      t.text :reflection
      t.text :prayer
      t.datetime :composed_at
      t.datetime :ai_attempted_at
      t.timestamps
    end
    add_index :daily_words, :date, unique: true
  end
end
