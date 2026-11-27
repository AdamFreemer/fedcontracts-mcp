FactoryBot.define do
  factory :recipient do
    sequence(:recipient_key) { |n| "recipient-#{n}" }
    sequence(:name) { |n| "Acme Corp #{n}" }
    state { "VA" }
    country { "USA" }
  end
end
