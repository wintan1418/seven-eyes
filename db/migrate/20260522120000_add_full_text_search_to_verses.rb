class AddFullTextSearchToVerses < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      ALTER TABLE verses
      ADD COLUMN text_vector tsvector
      GENERATED ALWAYS AS (to_tsvector('english', coalesce(text, ''))) STORED
    SQL
    add_index :verses, :text_vector, using: :gin, name: "index_verses_on_text_vector"
  end

  def down
    remove_index :verses, name: "index_verses_on_text_vector"
    remove_column :verses, :text_vector
  end
end
