# Fills awards.potential_end_date (the end date if every option is exercised) from
# USAspending's award detail endpoint, which the bulk search doesn't expose.
# Only awards that matter for expiring_contracts are checked, and each is
# re-checked only when USAspending reports a newer modification.
class EndDateEnricher
  MIN_AMOUNT = 100_000
  LOOKBACK_DAYS = 730 # ended up to 2 years ago: may still run on unexercised options
  LOOKAHEAD_DAYS = 365
  THREADS = 4
  MAX_FAILURE_RATE = 0.05

  Result = Data.define(:checked, :failed)

  def initialize(client: Usaspending::Client.new, today: Date.current, logger: Rails.logger, threads: THREADS)
    @client = client
    @today = today
    @logger = logger
    @threads = threads
  end

  def self.candidates(today: Date.current)
    Award.where(end_date: (today - LOOKBACK_DAYS)..(today + LOOKAHEAD_DAYS))
         .where(amount: MIN_AMOUNT..)
         .where("awards.details_checked_at IS NULL OR awards.details_checked_at < (awards.raw->>'Last Modified Date')::timestamp")
  end

  def call
    ids = self.class.candidates(today: @today).pluck(:id, :generated_internal_id)
    @logger.info("[EndDateEnricher] #{ids.size} awards to check")
    checked = Concurrent::AtomicFixnum.new
    failed = Concurrent::AtomicFixnum.new

    queue = Queue.new
    ids.each { |pair| queue << pair }
    @threads.times { queue << nil }

    workers = Array.new(@threads) do
      Thread.new do
        Rails.application.executor.wrap do
          while (pair = queue.pop)
            id, gid = pair
            if enrich(id, gid)
              n = checked.increment
              @logger.info("[EndDateEnricher] #{n}/#{ids.size}") if (n % 500).zero?
            else
              failed.increment
            end
          end
        end
      end
    end
    workers.each(&:join)

    result = Result.new(checked: checked.value, failed: failed.value)
    @logger.info("[EndDateEnricher] done: #{result.checked} checked, #{result.failed} failed")
    if ids.any? && result.failed > ids.size * MAX_FAILURE_RATE
      raise "EndDateEnricher: #{result.failed}/#{ids.size} lookups failed"
    end

    result
  end

  private

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
