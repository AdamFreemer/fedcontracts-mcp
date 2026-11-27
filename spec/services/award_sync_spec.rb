require "rails_helper"

RSpec.describe AwardSync do
  # Serves pages of recorded records; tracks the windows and pages requested.
  class FakeUsaspendingClient
    attr_reader :calls

    def initialize(pages: {}, agencies: [], error_on: nil)
      @pages = pages
      @agencies = agencies
      @error_on = error_on
      @calls = []
    end

    def toptier_agencies
      @agencies
    end

    def spending_by_award(start_date:, end_date:, naics_codes:, page:)
      @calls << { start_date:, end_date:, naics_codes:, page: }
      raise Usaspending::Client::Error, "boom" if @error_on == @calls.size

      results, has_next = @pages.fetch([ start_date, page ], [ [], false ])
      Usaspending::Client::Page.new(results:, has_next:)
    end
  end

  let(:records) { cassette_body("usaspending/spending_by_award_it_contracts").fetch("results") }
  let(:today) { Date.new(2026, 11, 27) }
  let(:agencies) { [ { "toptier_code" => "070", "abbreviation" => "DHS" }, { "toptier_code" => "075", "abbreviation" => "HHS" } ] }
  let(:logger) { Logger.new(IO::NULL) }

  def sync(client, days: 7)
    described_class.new(days:, client:, naics_codes: %w[541511], today:, logger:).call
  end

  describe "#call" do
    let(:start) { today - 7 }
    let(:client) do
      FakeUsaspendingClient.new(agencies:, pages: {
        [ start, 1 ] => [ records.first(6), true ],
        [ start, 2 ] => [ records.drop(6), false ]
      })
    end

    it "upserts agencies, recipients, and awards across pages" do
      result = sync(client)

      expect(result.upserted).to eq(10)
      expect(Award.count).to eq(10)
      expect(Recipient.count).to eq(records.map { |r| r["recipient_id"] }.uniq.size)
      expect(Agency.pluck(:toptier_code)).to match_array(records.map { |r| r["Awarding Agency Code"] }.uniq)
      expect(client.calls.map { |c| c[:page] }).to eq([ 1, 2 ])
    end

    it "links awards to their agency and recipient" do
      sync(client)

      award = Award.find_by!(generated_internal_id: "CONT_AWD_70SBUR27F00000012_7003_NNG15SD02B_8000")
      expect(award.awarding_agency.toptier_code).to eq("070")
      expect(award.recipient.name).to eq("PANAMERICA COMPUTERS, INC.")
      expect(award.raw["Award ID"]).to eq("70SBUR27F00000012")
    end

    it "fills agency abbreviations from the toptier reference" do
      sync(client)

      expect(Agency.find_by!(toptier_code: "070").abbreviation).to eq("DHS")
      expect(Agency.find_by!(toptier_code: "080").abbreviation).to be_nil
    end

    it "records a successful sync run" do
      result = sync(client)

      expect(result.sync_run.reload).to have_attributes(status: "succeeded", records_upserted: 10)
      expect(result.sync_run.finished_at).to be_present
      expect(SyncRun.data_freshness).to be_within(1.second).of(result.sync_run.finished_at)
    end

    it "is idempotent and updates changed fields on re-run" do
      sync(client)
      changed = records.map { |r| r["generated_internal_id"].start_with?("CONT_AWD_70SBUR27F") ? r.merge("Award Amount" => 99.5) : r }
      rerun_client = FakeUsaspendingClient.new(agencies:, pages: { [ start, 1 ] => [ changed, false ] })

      sync(rerun_client)

      expect(Award.count).to eq(10)
      expect(Award.find_by!(piid: "70SBUR27F00000012").amount).to eq(BigDecimal("99.5"))
      expect(SyncRun.succeeded.count).to eq(2)
    end

    it "dedupes records repeated within a page" do
      dup_client = FakeUsaspendingClient.new(agencies:, pages: { [ start, 1 ] => [ records + records.first(2), false ] })

      expect(sync(dup_client).upserted).to eq(10)
      expect(Award.count).to eq(10)
    end

    it "skips and counts invalid records without failing the run" do
      bad = records.first.merge("generated_internal_id" => nil)
      bad_client = FakeUsaspendingClient.new(agencies:, pages: { [ start, 1 ] => [ records.drop(1) + [ bad ], false ] })

      result = sync(bad_client)

      expect(result).to have_attributes(upserted: 9, skipped: 1)
      expect(result.sync_run.reload).to be_succeeded
    end

    it "marks the run failed, keeps the error, and re-raises when the API fails" do
      failing = FakeUsaspendingClient.new(agencies:, error_on: 1)

      expect { sync(failing) }.to raise_error(Usaspending::Client::Error)
      expect(SyncRun.last).to have_attributes(status: "failed", error: /boom/)
      expect(SyncRun.data_freshness).to be_nil
    end
  end

  describe "time windows" do
    it "splits the range into adjacent, non-overlapping 30-day windows ending today" do
      client = FakeUsaspendingClient.new(agencies:)

      sync(client, days: 65)

      windows = client.calls.map { |c| [ c[:start_date], c[:end_date] ] }
      expect(windows).to eq([
        [ today - 65, today - 36 ],
        [ today - 35, today - 6 ],
        [ today - 5, today ]
      ])
    end

    it "passes the configured NAICS codes" do
      client = FakeUsaspendingClient.new(agencies:)
      sync(client)
      expect(client.calls.map { |c| c[:naics_codes] }.uniq).to eq([ %w[541511] ])
    end
  end

  describe ".naics_codes" do
    around { |ex| original = ENV["SYNC_NAICS"]; ex.run; ENV["SYNC_NAICS"] = original }

    it "defaults to the IT/software set" do
      ENV.delete("SYNC_NAICS")
      expect(described_class.naics_codes).to eq(%w[541511 541512 541513 541519 518210])
    end

    it "reads a comma-separated SYNC_NAICS" do
      ENV["SYNC_NAICS"] = " 541511, 541330 ,"
      expect(described_class.naics_codes).to eq(%w[541511 541330])
    end
  end
end
