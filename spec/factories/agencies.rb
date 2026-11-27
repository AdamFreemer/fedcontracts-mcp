FactoryBot.define do
  factory :agency do
    sequence(:toptier_code) { |n| format("%03d", n) }
    name { "Department of Homeland Security" }
    abbreviation { "DHS" }
  end
end
