class CreateEventSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :event_sessions do |t|
      t.string :external_id, null: false
      t.string :title, null: false
      t.string :room
      t.datetime :starts_at
      t.datetime :ends_at
      t.datetime :external_updated_at

      t.timestamps
    end

    add_index :event_sessions, :external_id, unique: true
    add_index :event_sessions, :external_updated_at
  end
end
