require "rails_helper"

RSpec.describe Usaspending::AwardMapper do
  let(:records) { cassette_body("usaspending/spending_by_award_it_contracts").fetch("results") }
  let(:raw) { records.find { |r| r["generated_internal_id"].start_with?("CONT_AWD_70SBUR27F00000012") } }

  describe ".call on a recorded record" do
    subject(:result) { described_class.call(raw) }

    it "maps the agency" do
      expect(result.agency).to eq(toptier_code: "070", name: "Department of Homeland Security")
    end

    it "maps the recipient, keyed by USAspending recipient_id" do
      expect(result.recipient).to eq(
        recipient_key: "70e674ba-2d79-d6bb-37c8-a03189735d37-C",
        usaspending_recipient_id: "70e674ba-2d79-d6bb-37c8-a03189735d37-C",
        name: "PANAMERICA COMPUTERS, INC.",
        uei: "DPQEDJ6CXZM5",
        city: "LURAY",
        state: "VA",
        country: "USA"
      )
    end

    it "maps the award" do
      expect(result.award).to include(
        generated_internal_id: "CONT_AWD_70SBUR27F00000012_7003_NNG15SD02B_8000",
        piid: "70SBUR27F00000012",
        agency_toptier_code: "070",
        recipient_key: "70e674ba-2d79-d6bb-37c8-a03189735d37-C",
        awarding_sub_agency: "U.S. Citizenship and Immigration Services",
        amount: BigDecimal("11614859.76"),
        start_date: Date.new(2026, 11, 30),
        end_date: Date.new(2027, 11, 29),
        action_date: Date.new(2026, 11, 25),
        naics_code: "541519",
        naics_description: "OTHER COMPUTER RELATED SERVICES",
        psc_code: "DA10",
        place_of_performance_state: "MD"
      )
      expect(result.award[:description]).to start_with("SALESFORCE CRM SOFTWARE")
      expect(result.award[:raw]).to eq(raw)
    end

    it "produces attributes that save as valid records" do
      agency = Agency.create!(result.agency)
      recipient = Recipient.create!(result.recipient)
      award = Award.create!(result.award.except(:agency_toptier_code, :recipient_key)
                                        .merge(awarding_agency: agency, recipient: recipient))
      expect(award.reload.amount).to eq(BigDecimal("11614859.76"))
    end
  end

  it "maps every recorded record without error" do
    results = records.map { |r| described_class.call(r) }
    expect(results.map { |r| r.award[:generated_internal_id] }.uniq.size).to eq(records.size)
  end

  context "with missing or null fields" do
    it "falls back to a normalized-name recipient key when recipient_id is null" do
      result = described_class.call(raw.merge("recipient_id" => nil, "Recipient Name" => " PanAmerica Computers, Inc. "))
      expect(result.recipient[:recipient_key]).to eq("name:PANAMERICA COMPUTERS INC")
      expect(result.recipient[:usaspending_recipient_id]).to be_nil
      expect(result.award[:recipient_key]).to eq("name:PANAMERICA COMPUTERS INC")
    end

    it "uses a placeholder when the recipient name is also missing" do
      result = described_class.call(raw.merge("recipient_id" => nil, "Recipient Name" => nil))
      expect(result.recipient[:name]).to eq("UNKNOWN RECIPIENT")
      expect(result.recipient[:recipient_key]).to eq("name:UNKNOWN RECIPIENT")
    end

    it "tolerates null location, NAICS, PSC, dates, and amount" do
      result = described_class.call(raw.merge(
        "Recipient Location" => nil, "NAICS" => nil, "PSC" => nil,
        "End Date" => nil, "Start Date" => "", "Award Amount" => nil
      ))
      expect(result.recipient).to include(city: nil, state: nil, country: nil)
      expect(result.award).to include(naics_code: nil, psc_code: nil, end_date: nil, start_date: nil, amount: nil)
    end

    it "raises InvalidRecord without a generated_internal_id" do
      expect { described_class.call(raw.merge("generated_internal_id" => nil)) }
        .to raise_error(described_class::InvalidRecord, /generated_internal_id/)
    end

    it "raises InvalidRecord without an awarding agency code" do
      expect { described_class.call(raw.merge("Awarding Agency Code" => "")) }
        .to raise_error(described_class::InvalidRecord, /Awarding Agency Code/)
    end

    it "raises InvalidRecord on a malformed date" do
      expect { described_class.call(raw.merge("End Date" => "not-a-date")) }
        .to raise_error(described_class::InvalidRecord, /End Date/)
    end
  end

  describe ".normalize_name" do
    it "uppercases, strips punctuation, and squeezes whitespace" do
      expect(described_class.normalize_name("  Acme Corp., Inc. ")).to eq("ACME CORP INC")
    end
  end
end
