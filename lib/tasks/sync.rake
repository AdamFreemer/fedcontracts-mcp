namespace :sync do
  def stdout_logger
    $stdout.sync = true # show progress immediately when output is redirected (Heroku logs, files)
    ActiveSupport::Logger.new($stdout)
  end

  def run_award_sync(days)
    logger = stdout_logger
    result = AwardSync.new(days:, logger:).call
    puts "Sync ##{result.sync_run.id} succeeded: #{result.upserted} awards upserted, #{result.skipped} skipped " \
         "(#{days} days, NAICS #{AwardSync.naics_codes.join(',')})"
    run_end_date_sync(days, logger)
  end

  # Runs after the award sync. A failure here exits non-zero so the scheduler shows a
  # failed job; award data from the step before is already saved.
  def run_end_date_sync(days, logger)
    result = EndDateSync.new(days:, logger:).call
    puts "End dates: #{result.awards_updated} awards updated from #{result.rows} bulk rows, " \
         "#{result.parents_updated} parent companies filled"
  rescue StandardError => e
    abort "End-date sync failed (see sync_runs): #{e.message}"
  end

  desc "Backfill contract awards (default 730 days; override with DAYS=30), then fill end dates from bulk downloads"
  task backfill: :environment do
    run_award_sync(Integer(ENV.fetch("DAYS", AwardSync::BACKFILL_DAYS)))
  end

  desc "Sync the last 7 days of contract awards (overlapping window for late reports), then fill end dates from bulk downloads"
  task incremental: :environment do
    run_award_sync(AwardSync::INCREMENTAL_DAYS)
  end

  desc "Fill potential end dates and parent companies from bulk downloads (default 730 days; DAYS=7). Normally run by the sync tasks."
  task end_dates: :environment do
    run_end_date_sync(Integer(ENV.fetch("DAYS", AwardSync::BACKFILL_DAYS)), stdout_logger)
  end
end
