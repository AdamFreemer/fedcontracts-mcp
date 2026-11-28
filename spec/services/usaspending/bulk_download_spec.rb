require "rails_helper"

RSpec.describe Usaspending::BulkDownload do
  let(:request_url) { "https://api.usaspending.gov/api/v2/download/awards/" }
  let(:status_url) { "https://api.usaspending.gov/api/v2/download/status?file_name=PrimeAwardSummariesAndSubawards_X.zip" }
  let(:file_url) { "https://files.usaspending.gov/generated_downloads/PrimeAwardSummariesAndSubawards_X.zip" }
  let(:zip) { file_fixture("usaspending/bulk_contracts_sample.zip").binread }
  let(:downloader) { described_class.new(poll_interval: 0, poll_timeout: 5, logger: Logger.new(IO::NULL), retry_interval: 0) }
  let(:args) { { start_date: Date.new(2026, 11, 20), end_date: Date.new(2026, 11, 27), naics_codes: %w[541511 541512] } }

  def json(body) = { status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" } }

  def stub_request_download
    stub_request(:post, request_url).to_return(json(status_url:, file_url:, file_name: "PrimeAwardSummariesAndSubawards_X.zip"))
  end

  it "requests contracts for the window, polls until finished, and streams the prime contract rows" do
    request = stub_request_download.with { |req|
      f = JSON.parse(req.body)["filters"]
      f["time_period"] == [ { "start_date" => "2026-11-20", "end_date" => "2026-11-27", "date_type" => "action_date" } ] &&
        f["award_type_codes"] == %w[A B C D] && f["naics_codes"] == { "require" => %w[541511 541512] }
    }
    stub_request(:get, status_url).to_return(json(status: "running"), json(status: "finished", total_rows: 25, file_url:))
    stub_request(:get, file_url).to_return(status: 200, body: zip)

    rows = downloader.each_contract(**args).to_a

    expect(request).to have_been_requested
    expect(a_request(:get, status_url)).to have_been_made.twice
    expect(rows.size).to eq(25)
    expect(rows.first.keys).to include("contract_award_unique_key", "period_of_performance_potential_end_date",
                                       "period_of_performance_current_end_date", "recipient_uei", "recipient_parent_name")
    expect(rows.count { |r| r["period_of_performance_potential_end_date"][0, 10] > r["period_of_performance_current_end_date"] }).to eq(12)
  end

  it "raises when USAspending reports the download failed" do
    stub_request_download
    stub_request(:get, status_url).to_return(json(status: "failed", message: "boom"))

    expect { downloader.each_contract(**args).to_a }.to raise_error(described_class::Error, /failed to generate.*boom/)
  end

  it "times out when the download never finishes" do
    stub_request_download
    stub_request(:get, status_url).to_return(json(status: "running"))
    quick = described_class.new(poll_interval: 0, poll_timeout: 0, logger: Logger.new(IO::NULL))

    expect { quick.each_contract(**args).to_a }.to raise_error(described_class::TimedOut)
  end

  it "raises when the zip has no prime contracts CSV" do
    stub_request_download
    stub_request(:get, status_url).to_return(json(status: "finished", file_url:))
    empty_zip = Zip::OutputStream.write_buffer { |z| z.put_next_entry("Contracts_Subawards_1.csv"); z.write("a,b\n") }.string
    stub_request(:get, file_url).to_return(status: 200, body: empty_zip)

    expect { downloader.each_contract(**args).to_a }.to raise_error(described_class::Error, /No prime contracts CSV/)
  end

  it "labels dropped connections as likely rate limiting" do
    stub_request(:post, request_url).to_raise(Faraday::SSLError.new("SSL_read: unexpected eof"))

    expect { downloader.each_contract(**args).to_a }.to raise_error(Usaspending::Client::ConnectionRefused)
  end
end
