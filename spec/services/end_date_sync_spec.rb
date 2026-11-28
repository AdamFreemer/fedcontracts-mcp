require "rails_helper"

RSpec.describe EndDateSync do
  let(:today) { Date.new(2026, 11, 27) }
  let(:logger) { Logger.new(IO::NULL) }

  # Yields canned rows per window start; records the windows requested.
  class FakeDownloader
    attr_reader :windows

    # errors: either one error raised for every call, or { window_start => [errors to raise, in order] }.
    def initialize(rows_by_start = {}, error: nil, errors: {})
      @rows_by_start = rows_by_start
      @error = error
      @errors = errors
      @windows = []
    end

    def each_contract(start_date:, end_date:, naics_codes:, &block)
      @windows << [ start_date, end_date ]
      raise @error if @error

      queued = @errors[start_date]
      raise queued.shift if queued.present?

      @rows_by_start.fetch(start_date, []).each(&block)
    end
  end

  def row(gid, potential:, uei: nil, parent: nil)
    { "contract_award_unique_key" => gid, "period_of_performance_potential_end_date" => potential,
      "recipient_uei" => uei, "recipient_parent_name" => parent }
  end

  def sync(downloader, days: 7)
    described_class.new(days:, downloader:, naics_codes: %w[541511], today:, logger:).call
  end

  it "sets potential end dates and marks awards checked" do
    a = create(:award, end_date: today + 30)
    b = create(:award, end_date: today + 60)
    downloader = FakeDownloader.new({ today - 7 => [
      row(a.generated_internal_id, potential: "2029-12-31 00:00:00"),
      row(b.generated_internal_id, potential: "")
    ] })

    result = sync(downloader)

    expect(result).to have_attributes(rows: 2, awards_updated: 2)
    expect(a.reload).to have_attributes(potential_end_date: Date.new(2029, 12, 31), details_checked_at: be_present)
    expect(b.reload).to have_attributes(potential_end_date: nil, details_checked_at: be_present)
  end

  it "ignores rows for awards we don't have" do
    expect(sync(FakeDownloader.new({ today - 7 => [ row("CONT_AWD_UNKNOWN", potential: "2028-01-01") ] })).awards_updated).to eq(0)
  end

  it "fills parent company names by UEI" do
    r = create(:recipient, uei: "KMKUAFKECJ83", parent_name: nil)
    other = create(:recipient, uei: "OTHER0000001", parent_name: "KEEP ME")
    award = create(:award, recipient: r)

    result = sync(FakeDownloader.new({ today - 7 => [ row(award.generated_internal_id, potential: "", uei: "KMKUAFKECJ83", parent: "EXCELLA, LLC") ] }))

    expect(r.reload.parent_name).to eq("EXCELLA, LLC")
    expect(other.reload.parent_name).to eq("KEEP ME")
    expect(result.parents_updated).to eq(1)
  end

  it "reads the same windows as AwardSync" do
    downloader = FakeDownloader.new
    sync(downloader, days: 65)
    expect(downloader.windows).to eq(AwardSync.windows(days: 65, today:))
  end

  it "records a succeeded end_dates run that doesn't count as award freshness" do
    create(:award)
    sync(FakeDownloader.new)

    run = SyncRun.end_dates.last
    expect(run).to have_attributes(status: "succeeded")
    expect(run.details).to include("rows" => 0, "unchecked" => 1)
    expect(SyncRun.data_freshness).to be_nil
  end

  it "retries a window whose download fails to generate, then succeeds" do
    award = create(:award)
    failure = Usaspending::BulkDownload::Error.new("USAspending failed to generate X.zip: An error occurred.")
    downloader = FakeDownloader.new({ today - 7 => [ row(award.generated_internal_id, potential: "2028-01-01") ] },
                                    errors: { today - 7 => [ failure ] })

    result = sync(downloader)

    expect(downloader.windows.size).to eq(2)
    expect(result.failed_windows).to eq([])
    expect(award.reload.potential_end_date).to eq(Date.new(2028, 1, 1))
  end

  it "keeps going past a window that keeps failing, saves the rest, and records a failed run" do
    good = create(:award)
    failure = -> { Usaspending::BulkDownload::Error.new("An error occurred.") }
    first, second = AwardSync.windows(days: 40, today:)
    downloader = FakeDownloader.new({ second.first => [ row(good.generated_internal_id, potential: "2029-06-30") ] },
                                    errors: { first.first => [ failure.call, failure.call ] })

    expect { sync(downloader, days: 40) }.to raise_error(described_class::PartialFailure, /1 window\(s\) failed/)

    expect(good.reload.potential_end_date).to eq(Date.new(2029, 6, 30))
    run = SyncRun.end_dates.last
    expect(run).to have_attributes(status: "failed", error: /#{first.first}/)
    expect(run.details["failed_windows"]).to eq([ "#{first.first}..#{first.last}" ])
  end

  it "stops immediately when USAspending drops connections, leaving existing end dates alone" do
    award = create(:award, potential_end_date: Date.new(2030, 1, 1), details_checked_at: 1.day.ago)
    downloader = FakeDownloader.new(error: Usaspending::Client::ConnectionRefused.new("refused or dropped the connection"))

    expect { sync(downloader, days: 65) }.to raise_error(Usaspending::Client::ConnectionRefused)
    expect(downloader.windows.size).to eq(1)
    expect(SyncRun.end_dates.last).to have_attributes(status: "failed", error: /refused or dropped/)
    expect(award.reload.potential_end_date).to eq(Date.new(2030, 1, 1))
  end

  it "parses real bulk-file dates" do
    award = create(:award)
    sync(FakeDownloader.new({ today - 7 => [ row(award.generated_internal_id, potential: "2027-08-14 00:00:00") ] }))
    expect(award.reload.potential_end_date).to eq(Date.new(2027, 8, 14))
  end
end
