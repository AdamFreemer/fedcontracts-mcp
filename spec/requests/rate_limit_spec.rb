require "rails_helper"

RSpec.describe "Rate limiting", :rack_attack, type: :request do
  it "throttles /mcp per IP with a JSON-RPC 429 and Retry-After" do
    Rack::Attack::MCP_LIMIT.times { mcp_request("tools/list") }
    expect(response).to have_http_status(:ok)

    body = mcp_request("tools/list")

    expect(response).to have_http_status(:too_many_requests)
    expect(response.headers["Retry-After"].to_i).to be_between(1, 60)
    expect(body.dig("error", "message")).to include("Rate limit exceeded")
  end

  it "counts IPs separately" do
    Rack::Attack::MCP_LIMIT.times { mcp_request("tools/list") }
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json,
                 headers: McpHelpers::MCP_HEADERS.merge("REMOTE_ADDR" => "10.9.9.9")
    expect(response).to have_http_status(:ok)
  end

  it "does not throttle the Rails health check" do
    (Rack::Attack::MCP_LIMIT + 5).times { get "/up" }
    expect(response).to have_http_status(:ok)
  end
end
