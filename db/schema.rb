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

ActiveRecord::Schema[7.2].define(version: 2024_03_25_200103) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "events", force: :cascade do |t|
    t.string "eid", null: false
    t.string "pubkey", null: false
    t.integer "kind", null: false
    t.jsonb "tags", default: [], array: true
    t.string "content", null: false
    t.string "sig", null: false
    t.datetime "created_at", null: false
    t.string "topic", null: false
    t.string "session", null: false
    t.index ["eid"], name: "index_events_on_eid", unique: true
    t.index ["pubkey", "created_at"], name: "index_events_on_pubkey_and_created_at", unique: true
    t.index ["pubkey"], name: "index_events_on_pubkey"
    t.index ["topic"], name: "index_events_on_topic"
  end

  create_table "merkle_nodes", force: :cascade do |t|
    t.string "tree_hash", null: false
    t.bigint "event_id"
    t.string "calculated_hash"
    t.integer "begin_timestamp", null: false
    t.integer "end_timestamp", null: false
    t.boolean "full", default: false, null: false
    t.integer "level", null: false
    t.index ["begin_timestamp"], name: "index_merkle_nodes_on_begin_timestamp"
    t.index ["calculated_hash"], name: "index_merkle_nodes_on_calculated_hash", where: "(calculated_hash IS NULL)"
    t.index ["end_timestamp"], name: "index_merkle_nodes_on_end_timestamp"
    t.index ["event_id"], name: "index_merkle_nodes_on_event_id"
    t.index ["tree_hash"], name: "index_merkle_nodes_on_tree_hash"
  end

  add_foreign_key "merkle_nodes", "events"
end
