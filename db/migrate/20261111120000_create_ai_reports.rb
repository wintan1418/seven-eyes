# People can flag an AI answer (Rabbi, Find a Verse, prayers, illustrations) as
# offensive or wrong without leaving the app — Google Play's AI-generated
# content policy requires it. Admins read them on /admin.
class CreateAiReports < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_reports do |t|
      t.references :user, foreign_key: true
      t.string :kind, null: false
      t.string :context
      t.text :excerpt
      t.datetime :created_at, null: false
    end
    add_index :ai_reports, :created_at
  end
end
