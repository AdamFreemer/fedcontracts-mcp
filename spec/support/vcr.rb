require "webmock/rspec"
require "vcr"

# Block real HTTP in tests; USAspending responses come from recorded cassettes.
VCR.configure do |config|
  config.cassette_library_dir = Rails.root.join("spec/cassettes").to_s
  config.hook_into :webmock
  config.configure_rspec_metadata!
  config.default_cassette_options = { record: :once }
end
