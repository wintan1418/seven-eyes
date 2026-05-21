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

ActiveRecord::Schema[8.1].define(version: 2026_05_21_175542) do
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
    t.bigint "user_id", null: false
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
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  create_table "verses", force: :cascade do |t|
    t.bigint "book_id", null: false
    t.integer "chapter", null: false
    t.datetime "created_at", null: false
    t.text "text", null: false
    t.bigint "translation_id", null: false
    t.datetime "updated_at", null: false
    t.integer "verse_number", null: false
    t.index ["book_id", "chapter"], name: "index_verses_on_book_id_and_chapter"
    t.index ["translation_id", "book_id", "chapter", "verse_number"], name: "index_verses_unique_location", unique: true
    t.index ["translation_id"], name: "index_verses_on_translation_id"
  end

  add_foreign_key "cross_references", "books", column: "from_book_id"
  add_foreign_key "cross_references", "books", column: "to_book_id"
  add_foreign_key "panes", "studies"
  add_foreign_key "panes", "translations"
  add_foreign_key "sessions", "users"
  add_foreign_key "studies", "users"
  add_foreign_key "verses", "books"
  add_foreign_key "verses", "translations"
end
