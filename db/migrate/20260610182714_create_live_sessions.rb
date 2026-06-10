class CreateLiveSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :live_sessions do |t|
      t.references :study, null: false, foreign_key: true
      t.string :code, null: false
      t.string :osis
      t.integer :chapter
      t.integer :verse_start
      t.integer :verse_end
      t.string :translation_code
      t.integer :followers_count, null: false, default: 0
      t.datetime :ended_at

      t.timestamps
    end
    add_index :live_sessions, :code, unique: true
  end
end
