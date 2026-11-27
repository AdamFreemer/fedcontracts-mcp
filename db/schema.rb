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

ActiveRecord::Schema[8.1].define(version: 2026_11_28_000000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

  create_table "agencies", force: :cascade do |t|
    t.string "toptier_code", null: false
    t.string "name", null: false
    t.string "abbreviation"
    t.string "subtier_name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["toptier_code"], name: "index_agencies_on_toptier_code", unique: true
  end

  create_table "awards", force: :cascade do |t|
    t.string "generated_internal_id", null: false
    t.string "piid"
    t.bigint "recipient_id", null: false
    t.bigint "awarding_agency_id", null: false
    t.string "awarding_sub_agency"
    t.text "description"
    t.decimal "amount", precision: 15, scale: 2
    t.date "start_date"
    t.date "end_date"
    t.date "action_date"
    t.string "naics_code"
    t.string "naics_description"
    t.string "psc_code"
    t.string "place_of_performance_state"
    t.jsonb "raw", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action_date"], name: "index_awards_on_action_date"
    t.index ["awarding_agency_id"], name: "index_awards_on_awarding_agency_id"
    t.index ["description"], name: "index_awards_on_description", opclass: :gin_trgm_ops, using: :gin
    t.index ["end_date"], name: "index_awards_on_end_date"
    t.index ["generated_internal_id"], name: "index_awards_on_generated_internal_id", unique: true
    t.index ["naics_code"], name: "index_awards_on_naics_code"
    t.index ["recipient_id"], name: "index_awards_on_recipient_id"
    t.index ["start_date"], name: "index_awards_on_start_date"
  end

  create_table "recipients", force: :cascade do |t|
    t.string "recipient_key", null: false
    t.string "usaspending_recipient_id"
    t.string "name", null: false
    t.string "uei"
    t.string "parent_name"
    t.string "city"
    t.string "state"
    t.string "country"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_recipients_on_name_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["recipient_key"], name: "index_recipients_on_recipient_key", unique: true
    t.index ["uei"], name: "index_recipients_on_uei"
    t.index ["usaspending_recipient_id"], name: "index_recipients_on_usaspending_recipient_id"
  end

  create_table "sync_runs", force: :cascade do |t|
    t.datetime "started_at", null: false
    t.datetime "finished_at"
    t.string "status", default: "running", null: false
    t.integer "records_upserted", default: 0, null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["status", "finished_at"], name: "index_sync_runs_on_status_and_finished_at"
  end

  add_foreign_key "awards", "agencies", column: "awarding_agency_id"
  add_foreign_key "awards", "recipients"
end
