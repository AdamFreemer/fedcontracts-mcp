module CassetteHelpers
  # Parsed JSON response body of the first interaction in a recorded VCR cassette.
  def cassette_body(name)
    cassette = YAML.safe_load_file(Rails.root.join("spec/cassettes/#{name}.yml"))
    JSON.parse(cassette.dig("http_interactions", 0, "response", "body", "string"))
  end
end

RSpec.configure do |config|
  config.include CassetteHelpers
end
