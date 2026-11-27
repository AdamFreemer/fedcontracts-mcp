require "rails_helper"

RSpec.describe AgencyFilter do
  let!(:data) { build_query_fixtures }

  def matched_awards(query)
    described_class.new(query).apply(Award.all).to_a
  end

  describe "#apply and #matched_names" do
    it "matches a toptier abbreviation, case-insensitively" do
      expect(matched_awards("dhs")).to contain_exactly(data[:didit], data[:fema_cloud])
      expect(described_class.new("DHS").matched_names).to eq([ "Department of Homeland Security" ])
    end

    it "matches a sub-agency by derived acronym" do
      expect(matched_awards("USCIS")).to contain_exactly(data[:didit])
      expect(matched_awards("FEMA")).to contain_exactly(data[:fema_cloud])
      expect(matched_awards("FBI")).to contain_exactly(data[:doj_small])
    end

    it "matches a name fragment of 4+ characters" do
      expect(matched_awards("homeland")).to contain_exactly(data[:didit], data[:fema_cloud])
      expect(matched_awards("Emergency Management")).to contain_exactly(data[:fema_cloud])
    end

    it "does not substring-match short queries (ICE is not Justice)" do
      expect(matched_awards("ICE")).to be_empty
    end

    it "returns no awards when nothing matches" do
      expect(matched_awards("Department of Nothing")).to be_empty
      expect(described_class.new("Department of Nothing").matched_names).to be_empty
    end

    it "passes the scope through when blank" do
      expect(matched_awards("  ").size).to eq(Award.count)
      expect(described_class.new(nil)).to be_blank
    end

    it "escapes LIKE wildcards" do
      expect(matched_awards("%%%%")).to be_empty
    end
  end

  describe ".acronyms" do
    it "derives acronyms with and without a leading U.S." do
      expect(described_class.acronyms("U.S. Citizenship and Immigration Services")).to eq(%w[USCIS CIS])
      expect(described_class.acronyms("U.S. Customs and Border Protection")).to include("CBP")
      expect(described_class.acronyms("National Institutes of Health")).to eq([ "NIH" ])
    end
  end

  it "resolves known alias acronyms like CMS" do
    create(:award, awarding_sub_agency: "Centers for Medicare and Medicaid Services")
    expect(described_class.new("CMS").matched_names).to include("Centers for Medicare and Medicaid Services")
  end
end
