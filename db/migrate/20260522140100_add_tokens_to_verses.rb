class AddTokensToVerses < ActiveRecord::Migration[8.1]
  def change
    add_column :verses, :tokens, :jsonb
    add_index :verses, :tokens, using: :gin, name: "index_verses_on_tokens"
  end
end
