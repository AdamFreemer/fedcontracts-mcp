require "rails_helper"

RSpec.describe CompanyProfile do
  let!(:data) { build_query_fixtures }

  def profile(**args)
    described_class.new(today: QueryFixtures::TODAY, **args).call
  end

  context "with a unique name match" do
    subject(:result) { profile(name: "excella") }

    it "builds the profile" do
      expect(result).to be_found
      p = result.profile
      expect(p.name).to eq("EXCELLA, LLC")
      expect(p.ueis).to eq([ "KMKUAFKECJ83" ])
      expect(p.award_count).to eq(2)
      expect(p.total_amount).to eq(BigDecimal("67538173.03"))
    end

    it "includes top agencies and NAICS by amount" do
      expect(result.profile.top_agencies).to eq([
        { name: "Department of Homeland Security", abbreviation: "DHS", award_count: 2, total_amount: BigDecimal("67538173.03") }
      ])
      expect(result.profile.top_naics.map { |n| n[:code] }).to eq(%w[541512 518210])
    end

    it "includes a zero-filled 8-quarter trend by signed date" do
      trend = result.profile.quarterly_trend
      expect(trend.size).to eq(8)
      expect(trend.last).to eq(quarter: "2026-Q4", award_count: 1, total_amount: BigDecimal("65538173.03"))
      expect(trend.find { |q| q[:quarter] == "2026-Q3" }[:award_count]).to eq(1)
      expect(trend.first).to include(quarter: "2025-Q1", award_count: 0)
    end

    it "lists recent and soonest-expiring awards" do
      expect(result.profile.recent_awards).to eq([ data[:didit], data[:fema_cloud] ])
      expect(result.profile.expiring_awards).to eq([ data[:didit], data[:fema_cloud] ])
    end
  end

  it "finds a company by UEI" do
    result = profile(uei: "mhnfnj1j5rf5")
    expect(result).to be_found
    expect(result.profile.name).to eq("ODDBALL, INC.")
    expect(result.profile.expiring_awards).to eq([ data[:va_platform] ])
  end

  it "combines recipient rows that share a name across UEIs" do
    create(:recipient, name: "Oddball, Inc", uei: "ODDBALL00002", recipient_key: "oddball-2")
    result = profile(name: "oddball")
    expect(result).to be_found
    expect(result.profile.ueis).to contain_exactly("MHNFNJ1J5RF5", "ODDBALL00002")
    expect(result.profile.recipient_count).to eq(2)
  end

  it "returns candidates when the name matches several companies" do
    create(:award, recipient: create(:recipient, name: "AGILE SOLUTIONS LLC", recipient_key: "agile-sol"), amount: 1)
    result = profile(name: "agile")
    expect(result).to be_ambiguous
    expect(result.candidates.map(&:name)).to eq([ "AGILE SIX APPLICATIONS, INC", "AGILE SOLUTIONS LLC" ])
    expect(result.candidates.first).to have_attributes(award_count: 2, ueis: [ "AGILESIX0001" ])
  end

  it "only suggests fuzzy matches, never picks one" do
    result = profile(name: "Excela LLC")
    expect(result).to be_ambiguous
    expect(result.candidates.map(&:name)).to eq([ "EXCELLA, LLC" ])
  end

  it "returns not found when nothing matches" do
    expect(profile(name: "zzzqqq")).to be_not_found
  end

  it "requires a name or UEI" do
    expect { profile(name: " ") }.to raise_error(ArgumentError)
  end
end
