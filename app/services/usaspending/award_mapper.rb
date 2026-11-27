module Usaspending
  # Maps one spending_by_award result hash to attribute hashes for Agency, Recipient,
  # and Award. Associations are expressed as natural keys (toptier_code, recipient_key);
  # AwardSync resolves them to IDs after upserting agencies and recipients.
  class AwardMapper
    InvalidRecord = Class.new(StandardError)
    Result = Data.define(:agency, :recipient, :award)

    UNKNOWN_RECIPIENT = "UNKNOWN RECIPIENT".freeze

    def self.call(raw)
      new(raw).call
    end

    # "Acme Corp., Inc." -> "ACME CORP INC". Used as the recipient key fallback.
    def self.normalize_name(name)
      name.to_s.upcase.gsub(/[^A-Z0-9 ]/, " ").squish
    end

    def initialize(raw)
      @raw = raw
    end

    def call
      Result.new(agency: agency_attributes, recipient: recipient_attributes, award: award_attributes)
    end

    private

    attr_reader :raw

    def agency_attributes
      {
        toptier_code: required("Awarding Agency Code"),
        name: required("Awarding Agency")
      }
    end

    def recipient_attributes
      location = raw["Recipient Location"] || {}
      {
        recipient_key: recipient_key,
        usaspending_recipient_id: presence("recipient_id"),
        name: recipient_name,
        uei: presence("Recipient UEI"),
        city: location["city_name"].presence,
        state: location["state_code"].presence,
        country: location["location_country_code"].presence
      }
    end

    def award_attributes
      {
        generated_internal_id: required("generated_internal_id"),
        piid: presence("Award ID"),
        agency_toptier_code: required("Awarding Agency Code"),
        recipient_key: recipient_key,
        awarding_sub_agency: presence("Awarding Sub Agency"),
        description: presence("Description"),
        amount: decimal("Award Amount"),
        start_date: date("Start Date"),
        end_date: date("End Date"),
        # The search API does not expose the latest transaction date; the base
        # obligation date (when the award was signed) is the "won work" signal.
        action_date: date("Base Obligation Date"),
        naics_code: raw.dig("NAICS", "code").presence,
        naics_description: raw.dig("NAICS", "description").presence,
        psc_code: raw.dig("PSC", "code").presence,
        place_of_performance_state: presence("Place of Performance State Code"),
        raw: raw
      }
    end

    def recipient_key
      presence("recipient_id") || "name:#{self.class.normalize_name(recipient_name)}"
    end

    def recipient_name
      presence("Recipient Name") || UNKNOWN_RECIPIENT
    end

    def presence(key)
      value = raw[key]
      value.is_a?(String) ? value.strip.presence : value
    end

    def required(key)
      presence(key) || raise(InvalidRecord, "missing #{key.inspect} for award #{raw['generated_internal_id'].inspect}")
    end

    def decimal(key)
      value = raw[key]
      value.nil? ? nil : BigDecimal(value.to_s)
    rescue ArgumentError
      raise InvalidRecord, "bad #{key.inspect}: #{value.inspect}"
    end

    def date(key)
      value = presence(key)
      value.nil? ? nil : Date.iso8601(value.to_s[0, 10])
    rescue Date::Error
      raise InvalidRecord, "bad #{key.inspect}: #{value.inspect}"
    end
  end
end
