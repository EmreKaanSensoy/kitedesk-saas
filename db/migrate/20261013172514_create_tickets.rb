class CreateTickets < ActiveRecord::Migration[8.1]
  def change
    create_table :tickets do |t|
      t.string :ticket_number, null: false, index: { unique: true }
      t.string :title, null: false
      t.text :description, null: false
      t.string :priority, default: "medium", null: false
      t.string :status, default: "new_ticket", null: false
      t.string :category, default: "General"
      t.string :requester_name, null: false
      t.string :requester_email, null: false
      t.references :agent, null: true, foreign_key: true
      t.datetime :first_response_due_at
      t.datetime :first_responded_at
      t.datetime :resolution_due_at
      t.datetime :resolved_at
      t.datetime :closed_at
      t.boolean :sla_breached, default: false, null: false
      t.string :sla_breach_reason
      t.boolean :gratitude_loop_prevented, default: false, null: false

      t.timestamps
    end
    add_index :tickets, :status
    add_index :tickets, :priority
    add_index :tickets, :sla_breached
  end
end
