class CreateSessionSpeakers < ActiveRecord::Migration[8.1]
  def change
    create_table :session_speakers do |t|
      t.references :event_session, null: false, foreign_key: true
      t.references :speaker, null: false, foreign_key: true

      t.timestamps
    end

    add_index :session_speakers, [ :event_session_id, :speaker_id ], unique: true
  end
end
