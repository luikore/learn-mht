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

ActiveRecord::Schema[7.2].define(version: 2024_02_28_151229) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "events", force: :cascade do |t|
    t.string "signer", null: false
    t.string "session", null: false
    t.string "data", null: false
    t.string "hashed_data", null: false
    t.string "signed_hashed_data", null: false
    t.integer "timestamp", null: false
    t.index ["signer", "session"], name: "index_events_on_signer_and_session"
  end

  create_table "merkle_nodes", force: :cascade do |t|
    t.string "session", null: false
    t.bigint "event_id"
    t.string "calculated_hash"
    t.bigint "begin_ts", null: false
    t.bigint "end_ts", null: false
    t.boolean "full", default: false, null: false
    t.integer "level", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_merkle_nodes_on_event_id"
  end
end
