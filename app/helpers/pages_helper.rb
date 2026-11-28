module PagesHelper
  STATUS_LABELS = { "ok" => "Up to date", "stale" => "Stale", "never_synced" => "Not synced yet" }.freeze
  KIND_LABELS = { "awards" => "Award sync", "end_dates" => "End-date check" }.freeze

  # First paragraph of a tool's description, so the page stays in sync with the tool classes.
  def tool_summary(tool)
    tool.description.to_s.split(/\n\s*\n/).first.to_s.squish
  end

  # "about 3 hours ago", with the ISO timestamp in the markup and on hover.
  def relative_time(iso)
    return "never" if iso.blank?

    tag.time("#{time_ago_in_words(Time.zone.parse(iso))} ago", datetime: iso, title: iso)
  end

  def run_duration(run)
    return "running" if run[:finished_at].blank?

    seconds = (Time.zone.parse(run[:finished_at]) - Time.zone.parse(run[:started_at])).round
    seconds < 60 ? "#{seconds}s" : "#{seconds / 60}m #{seconds % 60}s"
  end

  def run_status(run)
    run[:rate_limited] ? "#{run[:status]}, rate limited" : run[:status]
  end
end
