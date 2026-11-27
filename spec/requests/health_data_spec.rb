require "rails_helper"

RSpec.describe "GET /health/data", type: :request do
  around { |ex| travel_to(Time.zone.parse("2026-11-27 12:00")) { ex.run } }

  it "is 503 before any successful sync" do
    get "/health/data"
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body).to include("status" => "never_synced", "last_successful_sync" => nil)
  end

  it "is 200 with a recent successful award sync" do
    create(:sync_run, :succeeded, finished_at: 2.hours.ago, records_upserted: 580)
    create(:award, amount: 500_000, end_date: Date.current + 30)

    get "/health/data"

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body).to include("status" => "ok", "age_hours" => 2.0, "awards" => 1, "end_date_backlog" => 1,
                            "consecutive_award_sync_failures" => 0)
    expect(body["last_award_sync"]).to include("status" => "succeeded", "records" => 580, "rate_limited" => false)
  end

  it "is 503 when stale, and reports consecutive failures and rate limiting without error text" do
    create(:sync_run, :succeeded, started_at: 50.hours.ago, finished_at: 49.hours.ago)
    create(:sync_run, :failed, started_at: 25.hours.ago, error: "Usaspending::Client::ConnectionRefused: USAspending refused or dropped the connection (often rate limiting; it clears on its own): Faraday::SSLError")
    create(:sync_run, :failed, started_at: 1.hour.ago, error: "Usaspending::Client::ConnectionRefused: USAspending refused or dropped the connection (often rate limiting; it clears on its own): Faraday::SSLError")

    get "/health/data"

    expect(response).to have_http_status(:service_unavailable)
    body = response.parsed_body
    expect(body).to include("status" => "stale", "consecutive_award_sync_failures" => 2)
    expect(body["last_award_sync"]).to include("status" => "failed", "rate_limited" => true)
    expect(response.body).not_to include("SSLError")
  end

  it "ignores end-date runs when judging freshness" do
    create(:sync_run, :succeeded, kind: "end_dates", finished_at: 1.hour.ago, details: { checked: 10 })
    get "/health/data"
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body.dig("last_end_date_run", "details")).to eq("checked" => 10)
  end
end
