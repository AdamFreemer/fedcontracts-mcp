require "rails_helper"

RSpec.describe RecentAwards do
  let!(:data) { build_query_fixtures }

  def recent(**args)
    described_class.new(today: QueryFixtures::TODAY, **args).call
  end

  it "lists awards signed in the last 30 days by default, newest first" do
    expect(recent.awards).to eq([ data[:doj_small], data[:va_platform], data[:va_cms], data[:didit] ])
  end

  it "excludes old contracts that are in the DB because of recent modifications" do
    expect(recent(agency: "VA", days: 3650).awards).to include(data[:va_old])
    expect(recent(agency: "VA").awards).not_to include(data[:va_old])
  end

  it "summarizes recipients by total amount across the whole window" do
    summaries = recent.recipients
    expect(summaries.map { |s| s.recipient.name }).to eq([ "ODDBALL, INC.", "EXCELLA, LLC", "AGILE SIX APPLICATIONS, INC" ])
    agile = summaries.last
    expect(agile.award_count).to eq(2)
    expect(agile.total_amount).to eq(BigDecimal("8383381"))
  end

  it "summarizes beyond the awards limit" do
    result = recent(limit: 1)
    expect(result.awards.size).to eq(1)
    expect(result.recipients.size).to eq(1)
    expect(result.total_count).to eq(4)
  end

  it "filters by agency" do
    result = recent(agency: "USCIS")
    expect(result.awards).to eq([ data[:didit] ])
    expect(result.matched_agencies).to eq([ "U.S. Citizenship and Immigration Services" ])
  end
end
