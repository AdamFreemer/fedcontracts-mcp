namespace :sync do
  def run_award_sync(days)
    logger = ActiveSupport::Logger.new($stdout)
    result = AwardSync.new(days:, logger:).call
    puts "Sync ##{result.sync_run.id} succeeded: #{result.upserted} awards upserted, #{result.skipped} skipped " \
         "(#{days} days, NAICS #{AwardSync.naics_codes.join(',')})"
  end

  desc "Backfill contract awards (default 365 days; override with DAYS=30)"
  task backfill: :environment do
    run_award_sync(Integer(ENV.fetch("DAYS", AwardSync::BACKFILL_DAYS)))
  end

  desc "Sync the last 7 days of contract awards (overlapping window for late reports)"
  task incremental: :environment do
    run_award_sync(AwardSync::INCREMENTAL_DAYS)
  end
end
