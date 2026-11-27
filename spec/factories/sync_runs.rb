FactoryBot.define do
  factory :sync_run do
    started_at { 1.hour.ago }
    status { "running" }

    trait :succeeded do
      status { "succeeded" }
      finished_at { 30.minutes.ago }
    end

    trait :failed do
      status { "failed" }
      finished_at { 30.minutes.ago }
      error { "boom" }
    end
  end
end
