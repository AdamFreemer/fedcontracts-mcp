# Fills awards.potential_end_date (the end date if every option is exercised) and
# recipients.parent_name from USAspending bulk downloads, which carry both; the
# search API used by AwardSync has neither. Uses the same 30-day windows as
# AwardSync. Any change to a contract's options is a modification, which moves its
# latest action date into the next daily window, so a 7-day daily run keeps this current.
class EndDateSync
  BATCH_SIZE = 1_000

  Result = Data.define(:sync_run, :rows, :awards_updated, :parents_updated)

  def initialize(days:, downloader: Usaspending::BulkDownload.new, naics_codes: AwardSync.naics_codes,
                 today: Date.current, logger: Rails.logger)
    @days = days
    @downloader = downloader
    @naics_codes = naics_codes
    @today = today
    @logger = logger
  end

  def call
    sync_run = SyncRun.create!(kind: "end_dates", started_at: Time.current)
    rows = awards_updated = parents_updated = 0

    AwardSync.windows(days: @days, today: @today).each do |window_start, window_end|
      end_dates = {}
      parents = {}
      @downloader.each_contract(start_date: window_start, end_date: window_end, naics_codes: @naics_codes) do |row|
        rows += 1
        gid = row["contract_award_unique_key"].presence or next
        end_dates[gid] = parse_date(row["period_of_performance_potential_end_date"])
        uei = row["recipient_uei"].presence
        parents[uei] = row["recipient_parent_name"].presence if uei && row["recipient_parent_name"].present?
      end
      awards_updated += update_end_dates(end_dates)
      parents_updated += update_parents(parents)
      @logger.info("[EndDateSync] #{window_start}..#{window_end}: #{end_dates.size} awards, #{parents.size} parents")
    end

    details = { rows:, awards_updated:, parents_updated:, unchecked: Award.where(details_checked_at: nil).count }
    sync_run.update!(status: :succeeded, finished_at: Time.current, records_upserted: awards_updated, details:)
    @logger.info("[EndDateSync] done: #{details}")
    Result.new(sync_run:, rows:, awards_updated:, parents_updated:)
  rescue StandardError => e
    sync_run&.update!(status: :failed, finished_at: Time.current, records_upserted: awards_updated.to_i,
                      details: { rows: rows.to_i }, error: "#{e.class}: #{e.message}".truncate(1000))
    raise
  end

  private

  # One UPDATE ... FROM (VALUES ...) per batch; awards not yet in our table are skipped.
  def update_end_dates(end_dates)
    now = Time.current
    end_dates.each_slice(BATCH_SIZE).sum do |batch|
      values = batch.map { |gid, date| Award.sanitize_sql_array([ "(?, ?::date)", gid, date ]) }.join(", ")
      Award.connection.update(Award.sanitize_sql_array([ <<~SQL, now ]))
        UPDATE awards SET potential_end_date = v.potential_end_date, details_checked_at = ?
        FROM (VALUES #{values}) AS v(generated_internal_id, potential_end_date)
        WHERE awards.generated_internal_id = v.generated_internal_id
      SQL
    end
  end

  def update_parents(parents)
    parents.group_by { |_uei, parent| parent }.sum do |parent, pairs|
      Recipient.where(uei: pairs.map(&:first)).where("parent_name IS DISTINCT FROM ?", parent).update_all(parent_name: parent)
    end
  end

  def parse_date(value)
    value.to_s[0, 10].presence&.then { |v| Date.iso8601(v) }
  rescue Date::Error
    nil
  end
end
