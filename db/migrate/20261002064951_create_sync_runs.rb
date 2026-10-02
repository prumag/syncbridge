class CreateSyncRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :sync_runs do |t|
      t.string :resource, null: false
      t.string :status, null: false, default: "running"
      t.datetime :started_at
      t.datetime :finished_at
      t.integer :records_fetched, null: false, default: 0
      t.integer :records_created, null: false, default: 0
      t.integer :records_updated, null: false, default: 0
      t.text :error_message

      t.timestamps
    end

    add_index :sync_runs, [ :resource, :status ]
  end
end
