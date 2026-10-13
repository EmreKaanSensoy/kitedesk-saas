class CreateTicketEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :ticket_events do |t|
      t.references :ticket, null: false, foreign_key: true
      t.string :event_type
      t.string :actor_name
      t.text :details
      t.text :metadata_json

      t.timestamps
    end
  end
end
