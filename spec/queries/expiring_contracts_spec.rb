require "rails_helper"

RSpec.describe ExpiringContracts do
  let!(:data) { build_query_fixtures }

  def expiring(**args)
    described_class.new(today: QueryFixtures::TODAY, **args).call
  end

  def statuses(result)
    result.items.to_h { |i| [ i.award.piid || i.award.description, i.status ] }
  end

  it "lists contracts with an end in the next 180 days by default, soonest event first" do
    expect(expiring.awards).to eq([ data[:va_cms], data[:doj_small], data[:didit], data[:dgib], data[:va_platform] ])
  end

  it "labels final periods, remaining options, and unchecked awards" do
    items = expiring.items.index_by(&:award)
    expect(items[data[:didit]]).to have_attributes(status: "final_period", final_end_date: QueryFixtures::TODAY + 60)
    expect(items[data[:va_platform]]).to have_attributes(status: "options_remaining", final_end_date: QueryFixtures::TODAY + 900)
    expect(items[data[:va_cms]].status).to eq("unknown")
  end

  it "includes contracts whose current period lapsed but whose options end in the window" do
    item = expiring.items.find { |i| i.award == data[:dgib] }
    expect(item).to have_attributes(status: "final_period", final_end_date: QueryFixtures::TODAY + 100)
  end

  it "treats a remaining-options contract as final once the window covers its potential end" do
    item = expiring(within_days: 1000).items.find { |i| i.award == data[:va_platform] }
    expect(item.status).to eq("final_period")
  end

  it "returns only final-period contracts with recompete_only" do
    expect(expiring(recompete_only: true).awards).to eq([ data[:didit], data[:dgib] ])
  end

  it "counts unchecked contracts in the window, even with recompete_only" do
    expect(expiring.unchecked_count).to eq(2)
    expect(expiring(recompete_only: true).unchecked_count).to eq(2)
  end

  it "excludes contracts that already ended or end after the window" do
    awards = expiring(within_days: 730).awards
    expect(awards).not_to include(data[:va_old])
    expect(awards).to include(data[:fema_cloud])
    expect(expiring.awards).not_to include(data[:fema_cloud])
  end

  it "includes the incumbent recipient" do
    expect(expiring(agency: "USCIS").awards.first.recipient.name).to eq("EXCELLA, LLC")
  end

  it "filters by within_days, minimum amount, and agency" do
    expect(expiring(within_days: 15).awards).to eq([ data[:va_cms] ])
    expect(expiring(min_amount: 1_000_000).awards).not_to include(data[:doj_small])
    expect(expiring(agency: "VA").awards).to eq([ data[:va_cms], data[:dgib], data[:va_platform] ])
  end

  it "applies the limit but reports the full count" do
    result = expiring(limit: 1)
    expect(result.awards.size).to eq(1)
    expect(result.total_count).to eq(5)
  end
end
