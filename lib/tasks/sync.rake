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
    run_end_date_enrichment(logger)
  end

  def run_end_date_enrichment(logger)
    result = EndDateEnricher.new(logger:).call
    puts "End dates: #{result.checked} checked, #{result.failed} failed, #{result.remaining} remaining"
    # Non-zero exit so the scheduler shows a failed job; the award data is already saved.
    abort "End-date lookups stopped early after repeated failures (see sync_runs)." if result.stopped_early
  end

  desc "Backfill contract awards (default 730 days; override with DAYS=30), then fetch potential end dates"
  task backfill: :environment do
    run_award_sync(Integer(ENV.fetch("DAYS", AwardSync::BACKFILL_DAYS)))
  end

  desc "Sync the last 7 days of contract awards (overlapping window for late reports), then fetch potential end dates"
  task incremental: :environment do
    run_award_sync(AwardSync::INCREMENTAL_DAYS)
  end

  desc "Fetch potential end dates for awards that need them (normally run by the sync tasks)"
  task end_dates: :environment do
    run_end_date_enrichment(stdout_logger)
  end
end
