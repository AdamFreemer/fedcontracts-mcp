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

      expect(tools.map { |t| t["name"] }).to eq(%w[search_awards])
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
