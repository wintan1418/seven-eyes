# Cached verse total per translation, so Translation.available can hide
# partially-seeded translations without counting ~31k rows on every render.
# BibleSeeder keeps it current; this backfills existing rows.
class AddVerseCountToTranslations < ActiveRecord::Migration[8.1]
  def up
    add_column :translations, :verse_count, :integer
    execute <<~SQL
      UPDATE translations
         SET verse_count = (SELECT COUNT(*) FROM verses WHERE verses.translation_id = translations.id)
    SQL
  end

  def down
    remove_column :translations, :verse_count
  end
end
