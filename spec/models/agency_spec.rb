require "rails_helper"

RSpec.describe Agency do
  it "is valid from the factory" do
    expect(build(:agency)).to be_valid
  end

  it "requires a name and toptier_code" do
    agency = Agency.new
    expect(agency).not_to be_valid
    expect(agency.errors.attribute_names).to include(:name, :toptier_code)
  end

  it "enforces unique toptier_code" do
    create(:agency, toptier_code: "070")
    expect(build(:agency, toptier_code: "070")).not_to be_valid
  end

  it "has awards via awarding_agency_id" do
    award = create(:award)
    expect(award.awarding_agency.awards).to contain_exactly(award)
  end
end
