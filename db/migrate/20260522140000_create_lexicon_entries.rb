class CreateLexiconEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :lexicon_entries do |t|
      t.string :strongs, null: false
      t.string :language, null: false
      t.string :lemma
      t.string :translit
      t.text :definition
      t.text :kjv_def
      t.text :derivation
      t.timestamps
    end
    add_index :lexicon_entries, :strongs, unique: true
  end
end
