require "rails_helper"

RSpec.describe "MCP endpoint", type: :request do
  describe "initialize" do
    it "completes the handshake and identifies the server" do
      body = mcp_request("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "rspec", version: "0" } })

      expect(response).to have_http_status(:ok)
      expect(body.dig("result", "serverInfo")).to include("name" => "fedcontracts", "version" => Fedcontracts::VERSION)
      expect(body.dig("result", "capabilities")).to have_key("tools")
      expect(body.dig("result", "instructions")).to include("USAspending")
      expect(response.headers["Mcp-Session-Id"]).to be_nil
    end
  end

  describe "tools/list" do
    it "lists the tools with valid, closed input schemas" do
      tools = mcp_request("tools/list").dig("result", "tools")

      expect(tools.map { |t| t["name"] }).to eq(%w[search_awards recent_awards expiring_contracts company_profile])
      tools.each do |tool|
        expect(tool["description"]).to be_present
        expect(tool["inputSchema"]).to include("type" => "object", "additionalProperties" => false)
        expect(JSONSchemer.valid_schema?(tool["inputSchema"])).to be(true)
        expect(tool.dig("annotations", "readOnlyHint")).to be(true)
      end
    end
  end

  describe "tools/call search_awards" do
    let!(:data) { build_query_fixtures }

    before { create(:sync_run, :succeeded, finished_at: Time.zone.parse("2026-11-27 06:00")) }

    around { |ex| travel_to(QueryFixtures::TODAY.in_time_zone.change(hour: 12)) { ex.run } }

    it "returns matching awards as structured content and text" do
      result = call_tool("search_awards", { keyword: "DID(IT)", agency: "USCIS" })

      expect(result["isError"]).to be(false)
      expect(result.dig("content", 0, "text")).to start_with("1 awards matched; showing 1")
      expect(JSON.parse(result.dig("content", 1, "text"))).to eq(result["structuredContent"])

      sc = result["structuredContent"]
      expect(sc).to include("total_count" => 1, "matched_agencies" => [ "U.S. Citizenship and Immigration Services" ])
      expect(sc.dig("data_freshness", "last_successful_sync")).to eq("2026-11-27T06:00:00Z")
      expect(sc["awards"].first).to include(
        "piid" => "70SBUR22F00000004",
        "recipient" => { "name" => "EXCELLA, LLC", "uei" => "KMKUAFKECJ83" },
        "agency_abbreviation" => "DHS",
        "amount" => 65_538_173.03,
        "signed_date" => "2026-11-07",
        "url" => a_string_starting_with("https://www.usaspending.gov/award/")
      )
    end

    it "applies limit and reports the full count" do
      sc = call_tool("search_awards", { limit: 1 })["structuredContent"]
      expect(sc).to include("total_count" => 4, "returned" => 1)
    end

    it "returns an empty result, not an error, when nothing matches" do
      result = call_tool("search_awards", { keyword: "no such thing" })
      expect(result["isError"]).to be(false)
      expect(result.dig("structuredContent", "awards")).to eq([])
    end

    it "reports an unmatched agency as a tool error with guidance" do
      result = call_tool("search_awards", { agency: "Department of Nothing" })
      expect(result["isError"]).to be(true)
      expect(result.dig("content", 0, "text")).to include("No agency matched")
    end

    it "rejects out-of-range, wrongly typed, and unknown arguments as tool errors" do
      [ { limit: 500 }, { days: 0 }, { days: "ninety" }, { state: "Virginia" }, { bogus: 1 } ].each do |args|
        result = call_tool("search_awards", args)
        expect(result["isError"]).to be(true), "expected #{args} to be rejected"
        expect(result.dig("content", 0, "text")).to start_with("Invalid arguments")
      end
    end

    it "hides internal errors from the client" do
      allow(AwardSearch).to receive(:new).and_raise(ActiveRecord::StatementInvalid, "PG::Error: SELECT secret FROM awards")
      allow(Rails.error).to receive(:report)

      body = mcp_request("tools/call", { name: "search_awards", arguments: {} })

      expect(body.to_json).not_to include("SELECT", "PG::", "secret")
      expect(Rails.error).to have_received(:report)
    end
  end

  describe "tools/call for the other tools" do
    let!(:data) { build_query_fixtures }

    around { |ex| travel_to(QueryFixtures::TODAY.in_time_zone.change(hour: 12)) { ex.run } }

    describe "recent_awards" do
      it "returns recent awards and a company summary" do
        result = call_tool("recent_awards", { agency: "VA" })

        expect(result["isError"]).to be(false)
        sc = result["structuredContent"]
        expect(sc["total_count"]).to eq(2)
        expect(sc["recipients"].map { |r| r["name"] }).to eq([ "ODDBALL, INC.", "AGILE SIX APPLICATIONS, INC" ])
        expect(sc["recipients"].first).to include("award_count" => 1, "total_amount" => 71_525_998.0)
        expect(sc["awards"].map { |a| a["piid"] }.first).to eq("36C10B22F0126")
        expect(sc).to have_key("data_freshness")
        expect(result.dig("content", 0, "text")).to include("top: ODDBALL, INC. $71,525,998")
      end

      it "rejects a window beyond 365 days and an unmatched agency" do
        expect(call_tool("recent_awards", { days: 400 })["isError"]).to be(true)
        expect(call_tool("recent_awards", { agency: "Nowhere Agency" }).dig("content", 0, "text")).to include("No agency matched")
      end
    end

    describe "expiring_contracts" do
      it "labels each contract's option status" do
        sc = call_tool("expiring_contracts", { agency: "VA" })["structuredContent"]

        by_piid = sc["contracts"].index_by { |c| c["piid"] }
        expect(by_piid["36C10D21N0007"]).to include("option_status" => "final_period", "final_end_date" => "2027-03-07",
                                                   "recipient" => include("name" => "ACCENTURE FEDERAL SERVICES LLC"))
        expect(by_piid["36C10B22F0126"]).to include("option_status" => "options_remaining", "potential_end_date" => "2029-05-15")
      end

      it "filters to recompetes and summarizes status counts" do
        result = call_tool("expiring_contracts", { recompete_only: true })

        expect(result.dig("structuredContent", "contracts").map { |c| c["piid"] }).to eq(%w[70SBUR22F00000004 36C10D21N0007])
        expect(result.dig("content", 0, "text")).to include("2 final_period, 0 options_remaining, 0 unknown")
      end

      it "rejects bad input" do
        expect(call_tool("expiring_contracts", { within_days: 0 })["isError"]).to be(true)
        expect(call_tool("expiring_contracts", { recompete_only: "yes" })["isError"]).to be(true)
      end
    end

    describe "company_profile" do
      it "returns a profile for a unique name" do
        result = call_tool("company_profile", { name: "Excella" })

        sc = result["structuredContent"]
        expect(sc["status"]).to eq("found")
        expect(sc["profile"]).to include("name" => "EXCELLA, LLC", "award_count" => 2, "ueis" => [ "KMKUAFKECJ83" ])
        expect(sc.dig("profile", "top_agencies", 0)).to include("abbreviation" => "DHS")
        expect(sc.dig("profile", "quarterly_trend").size).to eq(8)
        expect(sc.dig("profile", "recent_awards", 0, "piid")).to eq("70SBUR22F00000004")
        expect(result.dig("content", 0, "text")).to start_with("EXCELLA, LLC: 2 awards")
      end

      it "finds by UEI" do
        sc = call_tool("company_profile", { uei: "C47BNA8GM833" })["structuredContent"]
        expect(sc.dig("profile", "name")).to eq("ACCENTURE FEDERAL SERVICES LLC")
      end

      it "returns candidates when ambiguous" do
        create(:recipient, name: "ODDBALL ANALYTICS LLC", recipient_key: "oddball-analytics")
        result = call_tool("company_profile", { name: "oddball" })

        expect(result["isError"]).to be(false)
        expect(result.dig("structuredContent", "status")).to eq("ambiguous")
        expect(result.dig("structuredContent", "candidates").map { |c| c["name"] }).to include("ODDBALL, INC.", "ODDBALL ANALYTICS LLC")
        expect(result.dig("content", 0, "text")).to include("ask the user which one")
      end

      it "reports not found as a normal result" do
        sc = call_tool("company_profile", { name: "zzzqqq" })["structuredContent"]
        expect(sc["status"]).to eq("not_found")
      end

      it "requires a name or UEI and validates the UEI format" do
        expect(call_tool("company_profile", {}).dig("content", 0, "text")).to eq("Provide name or uei.")
        expect(call_tool("company_profile", { name: "  " })["isError"]).to be(true)
        expect(call_tool("company_profile", { uei: "short" })["isError"]).to be(true)
      end
    end
  end

  describe "protocol errors" do
    it "returns a JSON-RPC error for an unknown tool" do
      body = mcp_request("tools/call", { name: "nope", arguments: {} })
      expect(body.dig("error", "code")).to eq(-32602)
    end

    it "returns a parse error for invalid JSON" do
      post "/mcp", params: "not json", headers: McpHelpers::MCP_HEADERS
      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body).dig("error", "code")).to eq(-32700)
    end

    it "does not serve GET (no SSE stream in stateless mode)" do
      get "/mcp", headers: McpHelpers::MCP_HEADERS
      expect(response).to have_http_status(:method_not_allowed)
    end

    it "rejects requests for hosts that are not allowed" do
      host! "evil.example.com"
      mcp_request("tools/list")
      expect(response).to have_http_status(:forbidden)
    end

    it "accepts hosts listed in MCP_ALLOWED_HOSTS" do
      host! "fedcontracts.example.com"
      original = ENV["MCP_ALLOWED_HOSTS"]
      ENV["MCP_ALLOWED_HOSTS"] = "fedcontracts.example.com"
      expect(mcp_request("tools/list").dig("result", "tools")).to be_present
    ensure
      ENV["MCP_ALLOWED_HOSTS"] = original
    end
  end
end
