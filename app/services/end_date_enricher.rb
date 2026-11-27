# Fills awards.potential_end_date (the end date if every option is exercised) from
# USAspending's award detail endpoint, which the bulk search doesn't expose.
#
# USAspending is a free public API that blocks clients sending bursts of requests,
# so this runs one request at a time with a pause between them, checks the
# soonest-ending contracts first, caps each run, and stops early when requests
# keep failing. Whatever isn't checked waits for the next run.
class EndDateEnricher
  MIN_AMOUNT = 100_000
  LOOKBACK_DAYS = 730 # ended up to 2 years ago: may still run on unexercised options
  LOOKAHEAD_DAYS = 365
  MAX_PER_RUN = 5_000
  REQUEST_INTERVAL = 0.4 # seconds between requests (~1-2 requests/s with latency)
  MAX_CONSECUTIVE_FAILURES = 10

  Result = Data.define(:checked, :failed, :remaining, :stopped_early)

  def self.candidates(today: Date.current)
    Award.where(end_date: (today - LOOKBACK_DAYS)..(today + LOOKAHEAD_DAYS))
         .where(amount: MIN_AMOUNT..)
         .where("awards.details_checked_at IS NULL OR awards.details_checked_at < (awards.raw->>'Last Modified Date')::timestamp")
  end

  def initialize(client: Usaspending::Client.new, today: Date.current, logger: Rails.logger,
                 max_per_run: MAX_PER_RUN, request_interval: REQUEST_INTERVAL)
    @client = client
    @today = today
    @logger = logger
    @max_per_run = max_per_run
    @request_interval = request_interval
  end

  def call
    batch = prioritized_candidates.limit(@max_per_run).pluck(:id, :generated_internal_id)
    @logger.info("[EndDateEnricher] checking #{batch.size} awards (soonest-ending first)")
    checked = failed = consecutive_failures = 0
    stopped_early = false

    batch.each_with_index do |(id, gid), index|
      sleep(@request_interval) if index.positive? && @request_interval.positive?

      if enrich(id, gid)
        checked += 1
        consecutive_failures = 0
        @logger.info("[EndDateEnricher] #{checked}/#{batch.size}") if (checked % 250).zero?
      else
        failed += 1
        consecutive_failures += 1
        if consecutive_failures >= MAX_CONSECUTIVE_FAILURES
          @logger.warn("[EndDateEnricher] #{consecutive_failures} failures in a row; stopping until the next run")
          stopped_early = true
          break
        end
      end
    end

    result = Result.new(checked:, failed:, remaining: self.class.candidates(today: @today).count, stopped_early:)
    @logger.info("[EndDateEnricher] done: #{result.checked} checked, #{result.failed} failed, #{result.remaining} remaining")
    result
  end

  private

  # Contracts whose current end is soonest (and still ahead) first, then lapsed ones.
  def prioritized_candidates
    self.class.candidates(today: @today)
        .order(Arel.sql(Award.sanitize_sql_array([ "awards.end_date < ?, awards.end_date ASC, awards.id ASC", @today ])))
  end

  def enrich(id, gid)
    detail = @client.award(gid)
    potential = detail.dig("period_of_performance", "potential_end_date").to_s[0, 10].presence
    Award.where(id:).update_all(potential_end_date: potential && Date.iso8601(potential), details_checked_at: Time.current)
    true
  rescue Usaspending::Client::Error, Date::Error => e
    @logger.warn("[EndDateEnricher] #{gid}: #{e.message}")
    false
  end
end
