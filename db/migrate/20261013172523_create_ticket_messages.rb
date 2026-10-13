class CreateTicketMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :ticket_messages do |t|
      t.references :ticket, null: false, foreign_key: true
      t.string :sender_type, default: "customer", null: false
      t.string :sender_name, null: false
      t.string :sender_email
      t.text :body, null: false
      t.boolean :is_internal_note, default: false, null: false
      t.boolean :is_gratitude, default: false, null: false

      t.timestamps
    end
  end
end
