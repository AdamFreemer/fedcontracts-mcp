module Tools
  class CompanyProfile < Base
    tool_name "company_profile"
    title "Company federal contract profile"
    description <<~TEXT
      Profile of one company's federal IT/software prime contracts: total obligated, award
      count, top agencies and NAICS codes, awards signed per quarter (last 8 quarters), the 5
      most recently signed awards, and the 5 soonest-ending active awards.

      Look up by uei (exact) or name. Names match case-insensitively on the legal name ("Booz
      Allen", "Excella"); acronyms like "GDIT" usually won't match, so use the legal name. Rows
      sharing a name are combined (large firms have several UEIs). If the name matches several
      companies, or only approximately, the response has status "ambiguous" with candidates:
      ask the user to pick, then call again with the exact name or a uei.

      Covers prime contracts with activity in about the last 2 years, not lifetime totals.
      Subcontract work is not included. DoD data lags ~90 days.
    TEXT
    input_schema(
      type: "object",
      properties: {
        name: { type: "string", minLength: 2, maxLength: 200, description: "Company legal name or part of it" },
        uei: { type: "string", pattern: "^[A-Za-z0-9]{12}$", description: "12-character Unique Entity ID" }
      },
      additionalProperties: false
    )
    annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

    def self.call(name: nil, uei: nil, server_context: nil)
      return error("Provide name or uei.") if name.blank? && uei.blank?

      result = ::CompanyProfile.new(name:, uei:).call
      query = uei.presence || name

      if result.not_found?
        return respond("No company matched #{query.inspect}.", { status: "not_found", candidates: [] })
      end

      if result.ambiguous?
        candidates = result.candidates.map do |c|
          { name: c.name, ueis: c.ueis, award_count: c.award_count, total_amount: c.total_amount.to_f }
        end
        return respond("#{candidates.size} possible companies match #{query.inspect}; ask the user which one, " \
                       "then call again with the exact name or a uei.", { status: "ambiguous", candidates: })
      end

      p = result.profile
      profile = {
        name: p.name, ueis: p.ueis, total_amount: p.total_amount.to_f, award_count: p.award_count,
        top_agencies: p.top_agencies.map { |a| a.merge(total_amount: a[:total_amount].to_f) },
        top_naics: p.top_naics.map { |n| n.merge(total_amount: n[:total_amount].to_f) },
        quarterly_trend: p.quarterly_trend.map { |q| q.merge(total_amount: q[:total_amount].to_f) },
        recent_awards: p.recent_awards.map { |a| award_json(a) },
        expiring_awards: p.expiring_awards.map { |a| award_json(a) }
      }
      summary = "#{p.name}: #{p.award_count} awards, #{money(p.total_amount)} obligated" \
                "#{"; top agency #{p.top_agencies.first[:name]}" if p.top_agencies.any?}."
      respond(summary, { status: "found", profile: })
    end
  end
end
