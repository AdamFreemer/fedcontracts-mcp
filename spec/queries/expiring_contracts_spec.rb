require "rails_helper"

RSpec.describe ExpiringContracts do
  let!(:data) { build_query_fixtures }

  def expiring(**args)
    described_class.new(today: QueryFixtures::TODAY, **args).call
  end

  it "lists contracts ending in the next 180 days by default, soonest first" do
    expect(expiring.awards).to eq([ data[:va_cms], data[:doj_small], data[:didit], data[:va_platform] ])
  end

  it "excludes contracts that already ended or end after the window" do
    awards = expiring(within_days: 3650).awards
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
    expect(expiring(agency: "VA").awards).to eq([ data[:va_cms], data[:va_platform] ])
  end

  it "applies the limit but reports the full count" do
    result = expiring(limit: 1)
    expect(result.awards.size).to eq(1)
    expect(result.total_count).to eq(4)
  end
end
