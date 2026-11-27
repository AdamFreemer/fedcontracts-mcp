require "rails_helper"

RSpec.describe EndDateEnricher do
  let(:today) { Date.new(2026, 11, 27) }
  let(:logger) { Logger.new(IO::NULL) }
  let(:modified) { { "Last Modified Date" => "2026-11-20 10:00:00" } }

  # Returns award detail by generated_internal_id; raises for ids in `failing`.
  class FakeDetailClient
    def initialize(potential_ends, failing: [])
      @potential_ends = potential_ends
      @failing = failing
    end

    def award(gid)
      raise Usaspending::Client::Error, "boom" if @failing.include?(gid)

      { "period_of_performance" => { "potential_end_date" => @potential_ends[gid] } }
    end
  end

  def enrich(client)
    described_class.new(client:, today:, logger:, threads: 2).call
  end

  describe ".candidates" do
    it "selects $100k+ awards ending within 2 years back to 1 year ahead that need a check" do
      in_window = create(:award, amount: 500_000, end_date: today + 30, raw: modified)
      lapsed = create(:award, amount: 500_000, end_date: today - 700, raw: modified)
      create(:award, amount: 50_000, end_date: today + 30, raw: modified)       # too small
      create(:award, amount: 500_000, end_date: today + 400, raw: modified)     # too far ahead
      create(:award, amount: 500_000, end_date: today - 800, raw: modified)     # too far back
      create(:award, amount: 500_000, end_date: today + 30, raw: modified,
                     details_checked_at: Time.zone.parse("2026-11-21"))          # checked after last change

      expect(described_class.candidates(today:)).to contain_exactly(in_window, lapsed)
    end

    it "re-selects an award modified upstream after its last check" do
      award = create(:award, amount: 500_000, end_date: today + 30, raw: modified,
                             details_checked_at: Time.zone.parse("2026-11-19"))
      expect(described_class.candidates(today:)).to contain_exactly(award)
    end
  end

  describe "#call" do
    it "stores the potential end date and marks awards checked" do
      a = create(:award, amount: 500_000, end_date: today + 30, raw: modified)
      b = create(:award, amount: 500_000, end_date: today + 60, raw: modified)

      result = enrich(FakeDetailClient.new({ a.generated_internal_id => "2029-12-31 00:00:00", b.generated_internal_id => nil }))

      expect(result).to have_attributes(checked: 2, failed: 0)
      expect(a.reload).to have_attributes(potential_end_date: Date.new(2029, 12, 31), details_checked_at: be_present)
      expect(b.reload).to have_attributes(potential_end_date: nil, details_checked_at: be_present)
      expect(described_class.candidates(today:)).to be_empty
    end

    it "counts failures, leaves those awards unchecked, and tolerates a few" do
      awards = create_list(:award, 25, amount: 500_000, end_date: today + 30, raw: modified)
      failing = [ awards.first.generated_internal_id ]

      result = enrich(FakeDetailClient.new({}, failing:))

      expect(result).to have_attributes(checked: 24, failed: 1)
      expect(awards.first.reload.details_checked_at).to be_nil
    end

    it "raises when too many lookups fail" do
      awards = create_list(:award, 3, amount: 500_000, end_date: today + 30, raw: modified)

      expect { enrich(FakeDetailClient.new({}, failing: awards.map(&:generated_internal_id))) }
        .to raise_error(/3\/3 lookups failed/)
    end
  end
end
