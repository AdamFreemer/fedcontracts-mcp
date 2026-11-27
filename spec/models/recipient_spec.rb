require "rails_helper"

RSpec.describe Recipient do
  it "is valid from the factory" do
    expect(build(:recipient)).to be_valid
  end

  it "requires a name and recipient_key" do
    recipient = Recipient.new
    expect(recipient).not_to be_valid
    expect(recipient.errors.attribute_names).to include(:name, :recipient_key)
  end

  it "enforces unique recipient_key" do
    create(:recipient, recipient_key: "abc-R")
    expect(build(:recipient, recipient_key: "abc-R")).not_to be_valid
  end

  it "allows a null usaspending_recipient_id" do
    expect(build(:recipient, usaspending_recipient_id: nil)).to be_valid
  end
end
