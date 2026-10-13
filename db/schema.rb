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

ActiveRecord::Schema[8.1].define(version: 2026_10_13_172531) do
  create_table "agents", force: :cascade do |t|
    t.string "name"
    t.string "email"
    t.string "role"
    t.string "avatar_color"
    t.boolean "active"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "ticket_events", force: :cascade do |t|
    t.integer "ticket_id", null: false
    t.string "event_type"
    t.string "actor_name"
    t.text "details"
    t.text "metadata_json"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ticket_id"], name: "index_ticket_events_on_ticket_id"
  end

  create_table "ticket_messages", force: :cascade do |t|
    t.integer "ticket_id", null: false
    t.string "sender_type", default: "customer", null: false
    t.string "sender_name", null: false
    t.string "sender_email"
    t.text "body", null: false
    t.boolean "is_internal_note", default: false, null: false
    t.boolean "is_gratitude", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ticket_id"], name: "index_ticket_messages_on_ticket_id"
  end

  create_table "tickets", force: :cascade do |t|
    t.string "ticket_number", null: false
    t.string "title", null: false
    t.text "description", null: false
    t.string "priority", default: "medium", null: false
    t.string "status", default: "new_ticket", null: false
    t.string "category", default: "General"
    t.string "requester_name", null: false
    t.string "requester_email", null: false
    t.integer "agent_id"
    t.datetime "first_response_due_at"
    t.datetime "first_responded_at"
    t.datetime "resolution_due_at"
    t.datetime "resolved_at"
    t.datetime "closed_at"
    t.boolean "sla_breached", default: false, null: false
    t.string "sla_breach_reason"
    t.boolean "gratitude_loop_prevented", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id"], name: "index_tickets_on_agent_id"
    t.index ["priority"], name: "index_tickets_on_priority"
    t.index ["sla_breached"], name: "index_tickets_on_sla_breached"
    t.index ["status"], name: "index_tickets_on_status"
    t.index ["ticket_number"], name: "index_tickets_on_ticket_number", unique: true
  end

  add_foreign_key "ticket_events", "tickets"
  add_foreign_key "ticket_messages", "tickets"
  add_foreign_key "tickets", "agents"
end
