class CreateSyncRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :sync_runs do |t|
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.string :status, null: false, default: "running"
      t.integer :records_upserted, null: false, default: 0
      t.text :error

      t.timestamps
    end
    add_index :sync_runs, [ :status, :finished_at ]
  end
end
