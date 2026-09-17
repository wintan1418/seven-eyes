class CreateChapterAudios < ActiveRecord::Migration[8.1]
  def change
    create_table :chapter_audios do |t|
      t.references :translation, null: false, foreign_key: true
      t.references :book, null: false, foreign_key: true
      t.integer :chapter, null: false
      t.string :voice, null: false, default: ""
      t.integer :status, null: false, default: 0
      t.string :error
      t.datetime :generated_at

      t.timestamps
    end
    add_index :chapter_audios, %i[translation_id book_id chapter voice], unique: true,
              name: "index_chapter_audios_on_chapter_and_voice"
  end
end
