module Tools
  class ExpiringContracts < Base
    tool_name "expiring_contracts"
    title "Contracts ending soon"
    description <<~TEXT
      Federal IT/software contracts with an end date in the next N days (default 180), soonest
      first, with the incumbent company. Upcoming recompetes are hiring signals: incumbents
      staff up to defend, competitors staff up to bid, and the winner often hires the
      incumbent's people.

      Each contract has an option_status:
      - final_period: its last possible end date is in the window. Likely recompete.
      - options_remaining: the current period ends in the window but option years can extend
        it to final_end_date. Likely renewal with the same incumbent, a weaker signal.
      - unknown: option status not checked (awards under $100k).
      Set recompete_only=true to return only final_period contracts.

      Coverage: only contracts with activity in about the last 2 years are stored, so a quiet
      contract ending soon can be missing. Contracts that already ended are not listed. DoD
      data lags ~90 days. agency accepts an abbreviation, sub-agency acronym, or 4+ character
      name fragment; use min_amount to skip small orders.
    TEXT
    input_schema(
      type: "object",
      properties: {
        agency: { type: "string", description: "Agency abbreviation, sub-agency acronym, or name fragment (optional)" },
        within_days: { type: "integer", minimum: 1, maximum: 730, description: "Window ahead from today in days (default 180)" },
        min_amount: { type: "number", minimum: 0, description: "Minimum award amount in USD" },
        recompete_only: { type: "boolean", description: "Only contracts in their final period (default false)" },
        limit: { type: "integer", minimum: 1, maximum: 100, description: "Max contracts to return (default 25)" }
      },
      additionalProperties: false
    )
    annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

    def self.call(agency: nil, within_days: nil, min_amount: nil, recompete_only: false, limit: nil, server_context: nil)
      result = ::ExpiringContracts.new(agency:, within_days:, min_amount:, recompete_only:, limit:).call
      return unmatched_agency(agency) if agency.present? && result.matched_agencies.empty?

      contracts = result.items.map do |item|
        award_json(item.award).merge(option_status: item.status, final_end_date: item.final_end_date&.iso8601)
      end
      counts = contracts.group_by { |c| c[:option_status] }.transform_values(&:size)
      summary = "#{result.total_count} contracts ending in the window#{agency_note(result)}; showing #{contracts.size} " \
                "(#{::ExpiringContracts::STATUSES.map { |s| "#{counts.fetch(s, 0)} #{s}" }.join(', ')})."
      respond(summary, { total_count: result.total_count, returned: contracts.size, matched_agencies: result.matched_agencies,
                         contracts: })
    end
  end
end
