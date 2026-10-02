class CreateAttendees < ActiveRecord::Migration[8.1]
  def change
    create_table :attendees do |t|
      t.string :external_id, null: false
      t.string :name, null: false
      t.string :email
      t.string :company
      t.datetime :external_updated_at

      t.timestamps
    end

    add_index :attendees, :external_id, unique: true
    add_index :attendees, :external_updated_at
  end
end
