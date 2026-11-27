# Throttling is exercised in spec/requests/rate_limit_spec.rb only.
RSpec.configure do |config|
  config.before { Rack::Attack.enabled = false }
  config.before(:each, :rack_attack) do
    Rack::Attack.enabled = true
    Rack::Attack.cache.store.clear
  end
end
