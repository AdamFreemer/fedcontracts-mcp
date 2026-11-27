require "rails_helper"

RSpec.describe Award do
  it "is valid from the factory" do
    expect(build(:award)).to be_valid
  end

  it "requires a recipient, agency, and generated_internal_id" do
    award = Award.new
    expect(award).not_to be_valid
    expect(award.errors.attribute_names).to include(:recipient, :awarding_agency, :generated_internal_id)
  end

  it "enforces unique generated_internal_id at the database level" do
    existing = create(:award)
    dup = build(:award, generated_internal_id: existing.generated_internal_id,
                       recipient: existing.recipient, awarding_agency: existing.awarding_agency)
    expect { dup.save(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "stores amount with two decimal places" do
    award = create(:award, amount: "1234567.891")
    expect(award.reload.amount).to eq(BigDecimal("1234567.89"))
  end

  it "defaults raw to an empty hash" do
    expect(create(:award).reload.raw).to eq({})
  end

  describe "#usaspending_url" do
    it "links to the award page on usaspending.gov" do
      award = build(:award, generated_internal_id: "CONT_AWD_X_7001")
      expect(award.usaspending_url).to eq("https://www.usaspending.gov/award/CONT_AWD_X_7001")
    end
  end
end
