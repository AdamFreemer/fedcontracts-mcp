class AddKindAndDetailsToSyncRuns < ActiveRecord::Migration[8.1]
  def change
    # "awards" (AwardSync) or "end_dates" (EndDateEnricher). data_freshness reads awards runs only.
    add_column :sync_runs, :kind, :string, null: false, default: "awards"
    # Run-specific counts, e.g. { checked:, failed:, remaining: } for end_dates.
    add_column :sync_runs, :details, :jsonb, null: false, default: {}
    remove_index :sync_runs, [ :status, :finished_at ]
    add_index :sync_runs, [ :kind, :status, :finished_at ]
  end
end
