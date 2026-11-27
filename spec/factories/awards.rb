FactoryBot.define do
  factory :award do
    sequence(:generated_internal_id) { |n| "CONT_AWD_#{n}_7001" }
    sequence(:piid) { |n| "70CTD0#{n}" }
    recipient
    awarding_agency factory: :agency
    description { "Software development services" }
    amount { 1_000_000 }
    action_date { 10.days.ago.to_date }
    start_date { 10.days.ago.to_date }
    end_date { 1.year.from_now.to_date }
    naics_code { "541511" }
  end
end
