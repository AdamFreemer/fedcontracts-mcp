require "rails_helper"

RSpec.describe DataHealth do
  let(:now) { Time.zone.parse("2026-11-27 12:00") }

  def health = described_class.new(now:)

  it "is never_synced with no successful award sync" do
    create(:sync_run, :failed)
    expect(health.status).to eq("never_synced")
    expect(health.freshness).to include(stale: true, last_successful_sync: nil)
  end

  it "is ok within 36 hours of the last success" do
    create(:sync_run, :succeeded, finished_at: now - 35.hours)
    expect(health).to be_healthy
    expect(health.freshness).to include(stale: false)
  end

  it "is stale after 36 hours and tells the client to mention it" do
    create(:sync_run, :succeeded, finished_at: now - 50.hours)
    expect(health.status).to eq("stale")
    expect(health.freshness[:note]).to include("50 hours old", "Mention this to the user")
  end

  it "counts consecutive failed award syncs since the last success" do
    create(:sync_run, :failed, started_at: now - 72.hours)
    create(:sync_run, :succeeded, started_at: now - 48.hours, finished_at: now - 47.hours)
    create(:sync_run, :failed, started_at: now - 24.hours)
    create(:sync_run, :failed, started_at: now - 1.hour)
    create(:sync_run, kind: "end_dates", status: "failed", started_at: now - 30.minutes)

    expect(health.report[:consecutive_award_sync_failures]).to eq(2)
  end

  it "lists recent runs of both kinds, newest first, without error text" do
    create(:sync_run, :succeeded, started_at: now - 3.hours, finished_at: now - 2.hours, records_upserted: 580)
    create(:sync_run, kind: "end_dates", status: "failed", started_at: now - 1.hour, finished_at: now - 50.minutes,
                      error: "Faraday::SSLError: secret internals")

    runs = health.recent_runs

    expect(runs.map { |r| r.values_at(:kind, :status) }).to eq([ %w[end_dates failed], %w[awards succeeded] ])
    expect(runs.last).to include(records: 580, started_at: (now - 3.hours).iso8601)
    expect(runs.to_s).not_to include("secret internals", "SSLError")
    expect(health.recent_runs(limit: 1).size).to eq(1)
  end
end
