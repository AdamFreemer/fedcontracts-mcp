require "rails_helper"

RSpec.describe AwardSearch do
  let!(:data) { build_query_fixtures }

  def search(**args)
    described_class.new(today: QueryFixtures::TODAY, **args).call
  end

  it "defaults to awards signed in the last 90 days, newest first" do
    result = search
    expect(result.awards).to eq([ data[:doj_small], data[:va_platform], data[:va_cms], data[:didit] ])
    expect(result.total_count).to eq(4)
  end

  it "matches keywords in the description, including punctuation" do
    expect(search(keyword: "DID(IT)").awards).to eq([ data[:didit] ])
    expect(search(keyword: "va.gov").awards).to eq([ data[:va_platform] ])
  end

  it "treats LIKE wildcards in keywords literally" do
    expect(search(keyword: "%").awards).to be_empty
  end

  it "filters by agency and reports what matched" do
    result = search(agency: "VA")
    expect(result.awards).to contain_exactly(data[:va_platform], data[:va_cms])
    expect(result.matched_agencies).to eq([ "Department of Veterans Affairs" ])
  end

  it "filters by NAICS, state (case-insensitive), and minimum amount" do
    expect(search(naics_code: "541512").awards).to eq([ data[:didit] ])
    expect(search(state: "dc").awards).to eq([ data[:va_platform] ])
    expect(search(min_amount: 10_000_000).awards).to eq([ data[:va_platform], data[:didit] ])
  end

  it "widens the window with days" do
    expect(search(agency: "DHS", days: 365).awards).to eq([ data[:didit], data[:fema_cloud] ])
  end

  it "applies the limit but reports the full count" do
    result = search(limit: 2)
    expect(result.awards.size).to eq(2)
    expect(result.total_count).to eq(4)
  end
end
