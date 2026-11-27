module Tools
  class SearchAwards < Base
    tool_name "search_awards"
    title "Search contract awards"
    description <<~TEXT
      Search federal IT/software contract awards signed in the last N days (default 90),
      newest first. The window filters on signing date, so to find a long-running contract
      by name (signed years ago, still active) set days up to 3650. Use it to answer "who won what" questions, e.g. "Which companies won DHS
      cloud contracts this quarter?" or "Find awards mentioning DID(IT) at USCIS".

      Filters (all optional, combined with AND):
      - keyword: case-insensitive substring of the award description. Descriptions are
        truncated by USAspending to ~250 characters, so prefer distinctive words.
      - agency: abbreviation (DHS, VA, HHS), sub-agency acronym (USCIS, FEMA, CMS, IRS),
        or a name fragment of 4+ characters ("Homeland", "Veterans"). The response lists
        matched_agencies so you can confirm how it was interpreted.
      - naics_code, state (place of performance, 2-letter), min_amount (USD obligated).

      Dates: signed_date is when the award was signed; end_date is the current period of
      performance end; potential_end_date is the end if all options are exercised (known for
      awards >= $100k). Only prime contracts with activity in about the last 2 years are stored.
      Department of Defense data lags ~90 days. Returns at most `limit` awards (default 25,
      max 50, to keep responses within client size limits) plus total_count, each with a usaspending.gov URL. For "who won lately at an
      agency" prefer recent_awards; for contracts ending soon use expiring_contracts.
    TEXT
    input_schema(
      type: "object",
      properties: {
        keyword: { type: "string", maxLength: 200, description: "Substring to match in the award description" },
        agency: { type: "string", maxLength: 100, description: "Agency abbreviation, sub-agency acronym, or name fragment" },
        naics_code: { type: "string", description: "6-digit NAICS code, e.g. 541512", pattern: "^[0-9]{2,6}$" },
        state: { type: "string", description: "2-letter place-of-performance state code, e.g. VA", pattern: "^[A-Za-z]{2}$" },
        min_amount: { type: "number", minimum: 0, description: "Minimum award amount in USD" },
        days: { type: "integer", minimum: 1, maximum: 3650, description: "Look back this many days by signed date (default 90)" },
        limit: { type: "integer", minimum: 1, maximum: 50, description: "Max awards to return (default 25)" }
      },
      additionalProperties: false
    )
    annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

    def self.call(keyword: nil, agency: nil, naics_code: nil, state: nil, min_amount: nil, days: nil, limit: nil, server_context: nil)
      result = AwardSearch.new(keyword:, agency:, naics_code:, state:, min_amount:, days:, limit:).call

      return unmatched_agency(agency) if agency.present? && result.matched_agencies.empty?

      awards = result.awards.map { |a| award_json(a) }
      summary = "#{result.total_count} awards matched; showing #{awards.size}#{agency_note(result)}" \
                "#{", top: #{awards.first[:recipient][:name]} #{money(awards.first[:amount])}" if awards.any?}."
      respond(summary, { total_count: result.total_count, returned: awards.size, matched_agencies: result.matched_agencies, awards: })
    end
  end
end
