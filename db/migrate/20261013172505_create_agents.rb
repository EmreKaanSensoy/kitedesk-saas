class CreateAgents < ActiveRecord::Migration[8.1]
  def change
    create_table :agents do |t|
      t.string :name
      t.string :email
      t.string :role
      t.string :avatar_color
      t.boolean :active

      t.timestamps
    end
  end
end
