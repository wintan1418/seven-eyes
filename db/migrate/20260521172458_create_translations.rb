class CreateTranslations < ActiveRecord::Migration[8.1]
  def change
    create_table :translations do |t|
      t.string :code, null: false
      t.string :name, null: false
      t.string :language, null: false, default: "en"
      t.string :license, null: false, default: "public_domain"

      t.timestamps
    end
    add_index :translations, :code, unique: true
  end
end
