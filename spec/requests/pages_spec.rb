require "rails_helper"

RSpec.describe "GET /", type: :request do
  around { |ex| travel_to(Time.zone.parse("2026-11-27 12:00")) { ex.run } }

  def badge = Nokogiri::HTML(response.body).at_css(".badge")

  it "renders HTML with the connection URL built from the request host" do
    host! "fedcontracts.example.com"
    get "/"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/html")
    expect(response.body).to include("http://fedcontracts.example.com/mcp")
  end

  it "lists all four tools with their titles from the tool classes" do
    get "/"

    McpEndpoint::TOOLS.each do |tool|
      expect(response.body).to include(tool.name_value, CGI.escapeHTML(tool.title))
    end
    expect(response.body).to include("search_awards", "recent_awards", "expiring_contracts", "company_profile")
  end

  it "shows never_synced before any successful sync" do
    get "/"
    expect(badge["data-status"]).to eq("never_synced")
    expect(badge.text).to eq("Not synced yet")
  end

  it "shows ok with a recent successful sync, plus counts and recent runs" do
    create(:sync_run, :succeeded, started_at: 3.hours.ago, finished_at: 2.hours.ago, records_upserted: 1_580)
    create(:award)

    get "/"

    expect(badge["data-status"]).to eq("ok")
    expect(response.body).to include("about 2 hours ago", 2.hours.ago.iso8601, "1,580", "Award sync")
  end

  it "shows stale when the last success is old" do
    create(:sync_run, :succeeded, started_at: 50.hours.ago, finished_at: 49.hours.ago)
    get "/"
    expect(badge["data-status"]).to eq("stale")
  end

  it "never renders sync error text" do
    create(:sync_run, :succeeded, started_at: 50.hours.ago, finished_at: 49.hours.ago)
    create(:sync_run, :failed, started_at: 1.hour.ago,
                      error: "Usaspending::Client::ConnectionRefused: USAspending refused or dropped the connection: Faraday::SSLError at /app/lib/x.rb:12")
    create(:sync_run, kind: "end_dates", status: "failed", started_at: 30.minutes.ago, error: "PG::Error secret-internals")

    get "/"

    expect(response.body).to include("failed, rate limited")
    expect(response.body).not_to include("SSLError", "Faraday", "secret-internals", "PG::Error", "x.rb")
  end
end
