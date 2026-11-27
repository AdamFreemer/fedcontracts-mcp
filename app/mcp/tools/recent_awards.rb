module Tools
  class RecentAwards < Base
    tool_name "recent_awards"
    title "Recent contract wins"
    description <<~TEXT
      Who just won federal IT/software work and may be staffing up. Lists contracts signed in
      the last N days (default 30), newest first, plus a per-company summary (award count and
      total dollars across the whole window, largest first).

      Use for "Who won VA contracts this month?" or "Which companies are winning at USCIS?".
      agency accepts an abbreviation (DHS, VA, HHS), sub-agency acronym (USCIS, FEMA, CMS), or
      a 4+ character name fragment; matched_agencies shows how it was read.

      Interpreting results: a new award is a hiring signal mainly for services work (development,
      engineering, support). Software license and hardware resales (often via NASA SEWP orders)
      rarely mean new hires. signed_date is the award's signature date. Department of Defense
      data lags ~90 days, so recent DoD wins are sparse. Prime contracts only: subcontractors
      who do much of the hiring on large programs are not listed.
    TEXT
    input_schema(
      type: "object",
      properties: {
        agency: { type: "string", description: "Agency abbreviation, sub-agency acronym, or name fragment (optional)" },
        days: { type: "integer", minimum: 1, maximum: 365, description: "Look back this many days by signed date (default 30)" },
        limit: { type: "integer", minimum: 1, maximum: 100, description: "Max awards and companies to return (default 25)" }
      },
      additionalProperties: false
    )
    annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

    def self.call(agency: nil, days: nil, limit: nil, server_context: nil)
      result = ::RecentAwards.new(agency:, days:, limit:).call
      return unmatched_agency(agency) if agency.present? && result.matched_agencies.empty?

      awards = result.awards.map { |a| award_json(a) }
      recipients = result.recipients.map do |s|
        { name: s.recipient.name, uei: s.recipient.uei, award_count: s.award_count, total_amount: s.total_amount.to_f }
      end
      top = recipients.first
      summary = "#{result.total_count} awards signed in the window#{agency_note(result)}; " \
                "#{recipients.size} companies shown#{", top: #{top[:name]} #{money(top[:total_amount])}" if top}."
      respond(summary, { total_count: result.total_count, returned: awards.size, matched_agencies: result.matched_agencies,
                         recipients:, awards: })
    end
  end
end
