require "rails_helper"

RSpec.describe QueryLimits do
  describe ".limit" do
    it "defaults to 25 and clamps to 1..50" do
      expect(described_class.limit(nil)).to eq(25)
      expect(described_class.limit(500)).to eq(50)
      expect(described_class.limit(0)).to eq(1)
      expect(described_class.limit("10")).to eq(10)
    end

    it "rejects non-numeric input" do
      expect { described_class.limit("lots") }.to raise_error(ArgumentError)
    end
  end

  describe ".days" do
    it "uses the default and clamps to 1..3650" do
      expect(described_class.days(nil, default: 90)).to eq(90)
      expect(described_class.days(99_999, default: 90)).to eq(3650)
      expect(described_class.days(-5, default: 90)).to eq(1)
    end
  end
end
