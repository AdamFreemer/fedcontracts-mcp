# Pulls contract awards from USAspending for the last `days` days and upserts them
# into agencies, recipients, and awards. Records each run in sync_runs.
class AwardSync
  DEFAULT_NAICS = %w[541511 541512 541513 541519 518210].freeze
  # Two years: a contract in its final option year can go 12-18 months without
  # any action, and those are exactly the ones expiring_contracts must catch.
  BACKFILL_DAYS = 730
  INCREMENTAL_DAYS = 7
  # Monthly slices stay far under the API's 50k paging cap (largest seen: ~7.7k).
  WINDOW_DAYS = 30

  Result = Data.define(:sync_run, :upserted, :skipped)

  def self.naics_codes
    ENV.fetch("SYNC_NAICS", "").split(",").map(&:strip).reject(&:empty?).presence || DEFAULT_NAICS
  end

  def initialize(days:, client: Usaspending::Client.new, naics_codes: self.class.naics_codes,
                 today: Date.current, logger: Rails.logger)
    @days = days
    @client = client
    @naics_codes = naics_codes
    @today = today
    @logger = logger
    @upserted = 0
    @skipped = 0
  end

  def call
    sync_run = SyncRun.create!(kind: "awards", started_at: Time.current)
    abbreviations = fetch_abbreviations

    windows.each do |window_start, window_end|
      sync_window(window_start, window_end, abbreviations)
    end

    sync_run.update!(status: :succeeded, finished_at: Time.current, records_upserted: @upserted)
    logger.info("[AwardSync] done: #{@upserted} awards upserted, #{@skipped} skipped")
    Result.new(sync_run:, upserted: @upserted, skipped: @skipped)
  rescue StandardError => e
    sync_run&.update!(status: :failed, finished_at: Time.current, records_upserted: @upserted,
                      error: "#{e.class}: #{e.message}".truncate(1000))
    raise
  end

  private

  attr_reader :days, :client, :naics_codes, :today, :logger

  # Adjacent, non-overlapping [start, end] date ranges covering the last `days` days.
  def windows
    range_start = today - days
    (range_start..today).each_slice(WINDOW_DAYS).map { |slice| [ slice.first, slice.last ] }
  end

  def sync_window(window_start, window_end, abbreviations)
    page = 1
    loop do
      result = client.spending_by_award(start_date: window_start, end_date: window_end, naics_codes:, page:)
      upsert_page(result.results, abbreviations)
      logger.info("[AwardSync] #{window_start}..#{window_end} page #{page}: #{result.results.size} records")
      break unless result.has_next

      page += 1
    end
  end

  def upsert_page(raw_records, abbreviations)
    mapped = raw_records.filter_map { |raw| map(raw) }
    return if mapped.empty?

    ApplicationRecord.transaction do
      agency_ids = upsert_agencies(mapped, abbreviations)
      recipient_ids = upsert_recipients(mapped)
      upsert_awards(mapped, agency_ids, recipient_ids)
    end
  end

  def map(raw)
    Usaspending::AwardMapper.call(raw)
  rescue Usaspending::AwardMapper::InvalidRecord => e
    @skipped += 1
    logger.warn("[AwardSync] skipped record: #{e.message}")
    nil
  end

  def upsert_agencies(mapped, abbreviations)
    rows = mapped.map(&:agency).index_by { |a| a[:toptier_code] }.values
                 .map { |a| a.merge(abbreviation: abbreviations[a[:toptier_code]]) }
    Agency.upsert_all(rows, unique_by: :toptier_code, update_only: %i[name abbreviation])
    Agency.where(toptier_code: rows.pluck(:toptier_code)).pluck(:toptier_code, :id).to_h
  end

  def upsert_recipients(mapped)
    rows = mapped.map(&:recipient).index_by { |r| r[:recipient_key] }.values
    Recipient.upsert_all(rows, unique_by: :recipient_key)
    Recipient.where(recipient_key: rows.pluck(:recipient_key)).pluck(:recipient_key, :id).to_h
  end

  def upsert_awards(mapped, agency_ids, recipient_ids)
    rows = mapped.map(&:award).index_by { |a| a[:generated_internal_id] }.values.map do |a|
      a.except(:agency_toptier_code, :recipient_key)
       .merge(awarding_agency_id: agency_ids.fetch(a[:agency_toptier_code]),
              recipient_id: recipient_ids.fetch(a[:recipient_key]))
    end
    Award.upsert_all(rows, unique_by: :generated_internal_id)
    @upserted += rows.size
  end

  def fetch_abbreviations
    client.toptier_agencies.to_h { |a| [ a["toptier_code"], a["abbreviation"].presence ] }
  end
end
