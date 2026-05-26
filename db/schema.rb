# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_26_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "books", force: :cascade do |t|
    t.integer "chapter_count", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "osis_code", null: false
    t.integer "position", null: false
    t.integer "testament", null: false
    t.datetime "updated_at", null: false
    t.index ["osis_code"], name: "index_books_on_osis_code", unique: true
    t.index ["position"], name: "index_books_on_position", unique: true
  end

  create_table "commentaries", force: :cascade do |t|
    t.text "body", null: false
    t.bigint "book_id", null: false
    t.integer "chapter", null: false
    t.datetime "created_at", null: false
    t.string "source", null: false
    t.string "source_name", null: false
    t.datetime "updated_at", null: false
    t.index ["book_id", "chapter"], name: "index_commentaries_on_book_and_chapter"
    t.index ["book_id"], name: "index_commentaries_on_book_id"
    t.index ["source", "book_id", "chapter"], name: "index_commentaries_unique", unique: true
  end

  create_table "cross_references", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "from_book_id", null: false
    t.integer "from_chapter", null: false
    t.integer "from_verse", null: false
    t.bigint "to_book_id", null: false
    t.integer "to_chapter_end"
    t.integer "to_chapter_start", null: false
    t.integer "to_verse_end"
    t.integer "to_verse_start", null: false
    t.datetime "updated_at", null: false
    t.integer "votes", default: 0, null: false
    t.index ["from_book_id", "from_chapter", "from_verse"], name: "index_xrefs_on_from_location"
    t.index ["to_book_id"], name: "index_cross_references_on_to_book_id"
  end

  create_table "highlights", force: :cascade do |t|
    t.integer "char_end", null: false
    t.integer "char_start", null: false
    t.integer "color", default: 0, null: false
    t.datetime "created_at", null: false
    t.text "note"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "verse_id", null: false
    t.index ["user_id", "verse_id"], name: "index_highlights_on_user_id_and_verse_id"
    t.index ["user_id"], name: "index_highlights_on_user_id"
    t.index ["verse_id"], name: "index_highlights_on_verse_id"
  end

  create_table "lexicon_entries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "definition"
    t.text "derivation"
    t.text "kjv_def"
    t.string "language", null: false
    t.string "lemma"
    t.string "strongs", null: false
    t.string "translit"
    t.datetime "updated_at", null: false
    t.index ["strongs"], name: "index_lexicon_entries_on_strongs", unique: true
  end

  create_table "panes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "notes"
    t.integer "position", default: 0, null: false
    t.string "reference"
    t.bigint "study_id", null: false
    t.bigint "translation_id"
    t.datetime "updated_at", null: false
    t.index ["study_id", "position"], name: "index_panes_on_study_id_and_position", unique: true
    t.index ["study_id"], name: "index_panes_on_study_id"
    t.index ["translation_id"], name: "index_panes_on_translation_id"
  end

  create_table "plan_completions", force: :cascade do |t|
    t.datetime "completed_at", null: false
    t.datetime "created_at", null: false
    t.bigint "plan_day_id", null: false
    t.text "reflection"
    t.datetime "updated_at", null: false
    t.index ["plan_day_id"], name: "index_plan_completions_on_plan_day_id"
    t.index ["plan_day_id"], name: "index_plan_completions_unique", unique: true
  end

  create_table "plan_days", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "day_number", null: false
    t.bigint "reading_plan_id", null: false
    t.text "refs", default: "", null: false
    t.datetime "updated_at", null: false
    t.index ["reading_plan_id", "day_number"], name: "index_plan_days_unique", unique: true
    t.index ["reading_plan_id"], name: "index_plan_days_on_reading_plan_id"
  end

  create_table "reading_plans", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.date "start_date", null: false
    t.bigint "study_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "start_date"], name: "index_reading_plans_on_user_id_and_start_date"
    t.index ["user_id"], name: "index_reading_plans_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "studies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_opened_at"
    t.string "name", default: "Untitled Study", null: false
    t.integer "pane_count", default: 4, null: false
    t.boolean "sync_scroll", default: false, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["user_id", "last_opened_at"], name: "index_studies_on_user_id_and_last_opened_at"
    t.index ["user_id"], name: "index_studies_on_user_id"
  end

  create_table "translations", force: :cascade do |t|
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "language", default: "en", null: false
    t.string "license", default: "public_domain", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_translations_on_code", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.integer "font_size", default: 0, null: false
    t.datetime "guide_dismissed_at"
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  create_table "verses", force: :cascade do |t|
    t.bigint "book_id", null: false
    t.integer "chapter", null: false
    t.datetime "created_at", null: false
    t.text "text", null: false
    t.virtual "text_vector", type: :tsvector, as: "to_tsvector('english'::regconfig, COALESCE(text, ''::text))", stored: true
    t.jsonb "tokens"
    t.bigint "translation_id", null: false
    t.datetime "updated_at", null: false
    t.integer "verse_number", null: false
    t.index ["book_id", "chapter"], name: "index_verses_on_book_id_and_chapter"
    t.index ["text_vector"], name: "index_verses_on_text_vector", using: :gin
    t.index ["tokens"], name: "index_verses_on_tokens", using: :gin
    t.index ["translation_id", "book_id", "chapter", "verse_number"], name: "index_verses_unique_location", unique: true
    t.index ["translation_id"], name: "index_verses_on_translation_id"
  end

  add_foreign_key "commentaries", "books"
  add_foreign_key "cross_references", "books", column: "from_book_id"
  add_foreign_key "cross_references", "books", column: "to_book_id"
  add_foreign_key "highlights", "users"
  add_foreign_key "highlights", "verses"
  add_foreign_key "panes", "studies"
  add_foreign_key "panes", "translations"
  add_foreign_key "plan_completions", "plan_days"
  add_foreign_key "plan_days", "reading_plans"
  add_foreign_key "reading_plans", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "studies", "users"
  add_foreign_key "verses", "books"
  add_foreign_key "verses", "translations"
end
