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

ActiveRecord::Schema[7.2].define(version: 2024_03_25_200102) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "events", force: :cascade do |t|
    t.string "raw", null: false
    t.string "raw_hash", null: false
    t.string "signature", null: false
    t.integer "timestamp", null: false
    t.string "session", null: false
    t.integer "nonce", null: false
    t.string "signer", null: false
    t.index ["signer", "session", "nonce"], name: "index_events_on_signer_and_session_and_nonce", unique: true
    t.index ["signer", "session"], name: "index_events_on_signer_and_session"
  end

  create_table "merkle_nodes", force: :cascade do |t|
    t.string "tree_hash", null: false
    t.bigint "event_id"
    t.string "calculated_hash"
    t.integer "begin_nonce", null: false
    t.integer "end_nonce", null: false
    t.boolean "full", default: false, null: false
    t.integer "level", null: false
    t.index ["begin_nonce"], name: "index_merkle_nodes_on_begin_nonce"
    t.index ["calculated_hash"], name: "index_merkle_nodes_on_calculated_hash", where: "(calculated_hash IS NULL)"
    t.index ["end_nonce"], name: "index_merkle_nodes_on_end_nonce"
    t.index ["event_id"], name: "index_merkle_nodes_on_event_id"
    t.index ["tree_hash"], name: "index_merkle_nodes_on_tree_hash"
  end

  add_foreign_key "merkle_nodes", "events"
end
