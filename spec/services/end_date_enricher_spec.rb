require "rails_helper"

RSpec.describe EndDateEnricher do
  let(:today) { Date.new(2026, 11, 27) }
  let(:logger) { Logger.new(IO::NULL) }
  let(:modified) { { "Last Modified Date" => "2026-11-20 10:00:00" } }

  # Returns award detail by generated_internal_id; raises for ids in `failing`. Records call order.
  class FakeDetailClient
    attr_reader :calls

    def initialize(potential_ends = {}, failing: [])
      @potential_ends = potential_ends
      @failing = failing
      @calls = []
    end

    def award(gid)
      @calls << gid
      raise Usaspending::Client::Error, "boom" if @failing == :all || @failing.include?(gid)

      { "period_of_performance" => { "potential_end_date" => @potential_ends[gid] } }
    end
  end

  def enrich(client, **opts)
    described_class.new(client:, today:, logger:, request_interval: 0, **opts).call
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

      expect(result).to have_attributes(checked: 2, failed: 0, remaining: 0, stopped_early: false)
      expect(a.reload).to have_attributes(potential_end_date: Date.new(2029, 12, 31), details_checked_at: be_present)
      expect(b.reload).to have_attributes(potential_end_date: nil, details_checked_at: be_present)
    end

    it "checks the soonest-ending upcoming contracts first, then lapsed ones" do
      later = create(:award, amount: 500_000, end_date: today + 200, raw: modified)
      lapsed = create(:award, amount: 500_000, end_date: today - 100, raw: modified)
      soon = create(:award, amount: 500_000, end_date: today + 10, raw: modified)
      client = FakeDetailClient.new

      enrich(client)

      expect(client.calls).to eq([ soon, later, lapsed ].map(&:generated_internal_id))
    end

    it "caps each run and reports what remains" do
      create_list(:award, 5, amount: 500_000, end_date: today + 30, raw: modified)

      result = enrich(FakeDetailClient.new, max_per_run: 3)

      expect(result).to have_attributes(checked: 3, remaining: 2)
    end

    it "leaves failed awards unchecked and keeps going after isolated failures" do
      awards = create_list(:award, 5, amount: 500_000, end_date: today + 30, raw: modified)

      result = enrich(FakeDetailClient.new({}, failing: [ awards.first.generated_internal_id ]))

      expect(result).to have_attributes(checked: 4, failed: 1, remaining: 1, stopped_early: false)
      expect(awards.first.reload.details_checked_at).to be_nil
    end

    it "stops early after repeated consecutive failures, without raising" do
      create_list(:award, 15, amount: 500_000, end_date: today + 30, raw: modified)
      client = FakeDetailClient.new({}, failing: :all)

      result = enrich(client)

      expect(result).to have_attributes(checked: 0, failed: 10, stopped_early: true, remaining: 15)
      expect(client.calls.size).to eq(10)
    end
  end
end
