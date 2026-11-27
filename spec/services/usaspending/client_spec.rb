require "rails_helper"

RSpec.describe Usaspending::Client do
  let(:url) { "https://api.usaspending.gov/api/v2/search/spending_by_award/" }
  let(:client) { described_class.new(retry_interval: 0) }
  let(:args) do
    { start_date: Date.new(2026, 11, 13), end_date: Date.new(2026, 11, 27), naics_codes: %w[541511 541512 541513 541519 518210] }
  end

  describe "#spending_by_award", vcr: { cassette_name: "usaspending/spending_by_award_it_contracts" } do
    it "returns a page of contract results from the real API shape" do
      page = client.spending_by_award(**args, limit: 10)

      expect(page.results.size).to eq(10)
      expect(page.has_next).to be(true)
      expect(page.results.first).to include("generated_internal_id", "Awarding Agency Code", "Recipient Location", "NAICS")
    end
  end

  describe "#toptier_agencies", vcr: { cassette_name: "usaspending/toptier_agencies" } do
    it "returns agencies with toptier codes and abbreviations" do
      agencies = client.toptier_agencies

      expect(agencies.size).to be > 100
      expect(agencies.find { |a| a["toptier_code"] == "070" }).to include("abbreviation" => "DHS")
    end
  end

  describe "#award" do
    it "fetches award detail by generated_internal_id" do
      gid = "CONT_AWD_36C10D21N0007_3600_VA11816D1013_3600"
      stub_request(:get, "https://api.usaspending.gov/api/v2/awards/#{gid}/")
        .to_return(json_response_body({ "period_of_performance" => { "potential_end_date" => "2030-09-29 00:00:00" } }))

      expect(client.award(gid).dig("period_of_performance", "potential_end_date")).to eq("2030-09-29 00:00:00")
    end

    it "retries GETs on 5xx" do
      stub_request(:get, %r{/api/v2/awards/X/}).to_return({ status: 502 }).then.to_return(json_response_body({ "ok" => true }))
      expect(client.award("X")).to eq("ok" => true)
    end
  end

  describe "request shape" do
    it "sends contract type codes, the window, NAICS, and a sort field that is also in fields" do
      stub = stub_request(:post, url).with { |req|
        body = JSON.parse(req.body)
        body["filters"]["award_type_codes"] == %w[A B C D] &&
          body["filters"]["time_period"] == [ { "start_date" => "2026-11-13", "end_date" => "2026-11-27", "date_type" => "action_date" } ] &&
          body["filters"]["naics_codes"] == args[:naics_codes] &&
          body["fields"].include?(body["sort"]) &&
          body["limit"] == 100 && body["page"] == 2
      }.to_return(json_response(results: [], hasNext: false))

      page = client.spending_by_award(**args, page: 2, limit: 500)

      expect(stub).to have_been_requested
      expect(page.has_next).to be(false)
    end
  end

  describe "retries and errors" do
    it "retries on 429 and 5xx, then succeeds" do
      stub_request(:post, url)
        .to_return({ status: 429 }, { status: 503 })
        .then.to_return(json_response(results: [ { "generated_internal_id" => "X" } ], hasNext: false))

      page = client.spending_by_award(**args)

      expect(page.results.size).to eq(1)
      expect(a_request(:post, url)).to have_been_made.times(3)
    end

    it "raises Usaspending::Client::Error after exhausting retries" do
      stub_request(:post, url).to_return(status: 500)

      expect { client.spending_by_award(**args) }.to raise_error(Usaspending::Client::Error, /500/)
      expect(a_request(:post, url)).to have_been_made.times(5)
    end

    it "does not retry a 422 and raises" do
      stub_request(:post, url).to_return(status: 422, body: { detail: "over the maximum result limit" }.to_json)

      expect { client.spending_by_award(**args) }.to raise_error(Usaspending::Client::Error, /422/)
      expect(a_request(:post, url)).to have_been_made.once
    end

    it "raises on timeouts after retrying" do
      stub_request(:post, url).to_timeout

      expect { client.spending_by_award(**args) }.to raise_error(Usaspending::Client::Error)
    end

    it "raises on an unexpected response shape" do
      stub_request(:post, url).to_return(json_response_body({ "unexpected" => true }))

      expect { client.spending_by_award(**args) }.to raise_error(Usaspending::Client::Error, /shape/)
    end
  end

  def json_response(results:, hasNext:)
    json_response_body({ results: results, page_metadata: { page: 1, hasNext: hasNext } })
  end

  def json_response_body(body)
    { status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" } }
  end
end
