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

ActiveRecord::Schema[8.1].define(version: 2026_10_11_103001) do
  create_table "attendees", force: :cascade do |t|
    t.string "external_id", null: false
    t.string "name", null: false
    t.string "email"
    t.string "company"
    t.datetime "external_updated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["external_id"], name: "index_attendees_on_external_id", unique: true
    t.index ["external_updated_at"], name: "index_attendees_on_external_updated_at"
  end

  create_table "event_sessions", force: :cascade do |t|
    t.string "external_id", null: false
    t.string "title", null: false
    t.string "room"
    t.datetime "starts_at"
    t.datetime "ends_at"
    t.datetime "external_updated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["external_id"], name: "index_event_sessions_on_external_id", unique: true
    t.index ["external_updated_at"], name: "index_event_sessions_on_external_updated_at"
  end

  create_table "session_speakers", force: :cascade do |t|
    t.integer "event_session_id", null: false
    t.integer "speaker_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_session_id", "speaker_id"], name: "index_session_speakers_on_event_session_id_and_speaker_id", unique: true
    t.index ["event_session_id"], name: "index_session_speakers_on_event_session_id"
    t.index ["speaker_id"], name: "index_session_speakers_on_speaker_id"
  end

  create_table "speakers", force: :cascade do |t|
    t.string "external_id", null: false
    t.string "name", null: false
    t.string "company"
    t.string "job_title"
    t.datetime "external_updated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["external_id"], name: "index_speakers_on_external_id", unique: true
    t.index ["external_updated_at"], name: "index_speakers_on_external_updated_at"
  end

  create_table "sync_runs", force: :cascade do |t|
    t.string "resource", null: false
    t.string "status", default: "running", null: false
    t.datetime "started_at"
    t.datetime "finished_at"
    t.integer "records_fetched", default: 0, null: false
    t.integer "records_created", default: 0, null: false
    t.integer "records_updated", default: 0, null: false
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["resource", "status"], name: "index_sync_runs_on_resource_and_status"
  end

  add_foreign_key "session_speakers", "event_sessions"
  add_foreign_key "session_speakers", "speakers"
end
