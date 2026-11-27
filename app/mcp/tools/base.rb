module Tools
  # Shared response helpers. Each tool stays a thin layer over a query object.
  class Base < MCP::Tool
    class << self
      private

      # Structured content for clients that read it, plus a text summary and the same
      # JSON as text for clients that only read content blocks.
      def respond(summary, data)
        payload = data.merge(data_freshness: data_freshness)
        MCP::Tool::Response.new(
          [ { type: "text", text: summary }, { type: "text", text: JSON.generate(payload) } ],
          structured_content: payload
        )
      end

      def unmatched_agency(agency)
        error("No agency matched #{agency.inspect}. Try an abbreviation (DHS, VA), a sub-agency acronym (USCIS), or part of the name.")
      end

      def agency_note(result)
        result.matched_agencies.any? ? " (agency: #{result.matched_agencies.join(', ')})" : ""
      end

      def error(message)
        MCP::Tool::Response.new([ { type: "text", text: message } ], error: true)
      end

      def data_freshness
        last = SyncRun.data_freshness
        {
          last_successful_sync: last&.iso8601,
          note: last ? "Data reflects USAspending as of the last successful sync." : "No successful sync yet; data may be empty."
        }
      end

      def award_json(award)
        {
          piid: award.piid,
          recipient: { name: award.recipient.name, uei: award.recipient.uei },
          agency: award.awarding_agency.name,
          agency_abbreviation: award.awarding_agency.abbreviation,
          sub_agency: award.awarding_sub_agency,
          amount: award.amount&.to_f,
          description: award.description,
          signed_date: award.action_date&.iso8601,
          start_date: award.start_date&.iso8601,
          end_date: award.end_date&.iso8601,
          potential_end_date: award.potential_end_date&.iso8601,
          naics_code: award.naics_code,
          naics_description: award.naics_description,
          psc_code: award.psc_code,
          place_of_performance_state: award.place_of_performance_state,
          url: award.usaspending_url
        }
      end

      def money(amount)
        "$#{ActiveSupport::NumberHelper.number_to_delimited(amount.to_f.round)}"
      end
    end
  end
end
