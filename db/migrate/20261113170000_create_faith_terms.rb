class CreateFaithTerms < ActiveRecord::Migration[8.1]
  def change
    create_table :faith_terms do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :aliases, array: true, null: false, default: []
      t.text :short_definition, null: false
      t.text :new_believer
      t.text :explanation
      t.string :root_strongs, array: true, null: false, default: []
      t.string :key_references, array: true, null: false, default: []
      t.string :related_slugs, array: true, null: false, default: []
      t.integer :position, null: false, default: 0
      t.integer :status, null: false, default: 0
      t.string :reviewed_by
      t.datetime :reviewed_at
      # Set when someone edits the text on the site, so a re-seed never
      # overwrites a pastor's changes.
      t.datetime :edited_at
      t.timestamps
    end
    add_index :faith_terms, :slug, unique: true
    add_index :faith_terms, %i[status position]

    add_column :users, :reviewer, :boolean, null: false, default: false
  end
end
