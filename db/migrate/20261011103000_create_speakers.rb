class CreateSpeakers < ActiveRecord::Migration[8.1]
  def change
    create_table :speakers do |t|
      t.string :external_id, null: false
      t.string :name, null: false
      t.string :company
      t.string :job_title
      t.datetime :external_updated_at

      t.timestamps
    end

    add_index :speakers, :external_id, unique: true
    add_index :speakers, :external_updated_at
  end
end
