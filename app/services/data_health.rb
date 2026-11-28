# Summarizes pipeline health from sync_runs: how fresh the award data is, whether
# recent syncs failed, and how much end-date enrichment is outstanding. Feeds
# GET /health/data (for an external uptime monitor), data_freshness in tool
# responses, and the landing page status panel.
class DataHealth
  STALE_AFTER = 36.hours # daily sync plus slack

  def initialize(now: Time.current)
    @now = now
  end

  def healthy?
    status == "ok"
  end

  # "ok", "stale" (no successful award sync within STALE_AFTER), or "never_synced".
  def status
    return "never_synced" if last_success.nil?

    @now - last_success > STALE_AFTER ? "stale" : "ok"
  end

  def last_success
    return @last_success if defined?(@last_success)

    @last_success = SyncRun.data_freshness
  end

  def age_hours
    last_success && ((@now - last_success) / 1.hour).round(1)
  end

  # Brief freshness block included in every tool response.
  def freshness
    {
      last_successful_sync: last_success&.iso8601,
      stale: status != "ok",
      note: freshness_note
    }
  end

  # Full report for /health/data and the status panel. No internal error text:
  # this is public, so failures are summarized, not echoed.
  def report
    last_awards = SyncRun.awards.order(started_at: :desc).first
    last_end_dates = SyncRun.end_dates.order(started_at: :desc).first
    {
      status:,
      checked_at: @now.iso8601,
      last_successful_sync: last_success&.iso8601,
      age_hours:,
      stale_after_hours: (STALE_AFTER / 1.hour).to_i,
      consecutive_award_sync_failures: consecutive_failures,
      last_award_sync: run_summary(last_awards),
      last_end_date_run: run_summary(last_end_dates),
      awards_without_end_dates: Award.where(details_checked_at: nil).count,
      awards: Award.count
    }
  end

  private

  def freshness_note
    case status
    when "ok" then "Data reflects USAspending as of the last successful sync."
    when "stale" then "Data is #{age_hours.round} hours old; the daily sync has not succeeded recently. Mention this to the user."
    else "No successful sync yet; data may be empty."
    end
  end

  def consecutive_failures
    SyncRun.awards.where.not(status: :running).order(started_at: :desc).limit(30).pluck(:status)
           .take_while { |s| s == "failed" }.size
  end

  def run_summary(run)
    return nil unless run

    {
      status: run.status,
      started_at: run.started_at.iso8601,
      finished_at: run.finished_at&.iso8601,
      records: run.records_upserted,
      rate_limited: run.error.to_s.include?("refused or dropped the connection"),
      details: run.details.presence
    }.compact
  end
end
