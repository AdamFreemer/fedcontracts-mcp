require "rails_helper"

RSpec.describe "MCP bearer token", type: :request do
  around do |ex|
    original = ENV["MCP_BEARER_TOKEN"]
    ENV["MCP_BEARER_TOKEN"] = "s3cret-token"
    ex.run
  ensure
    ENV["MCP_BEARER_TOKEN"] = original
  end

  def list_tools(headers = {})
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json, headers: McpHelpers::MCP_HEADERS.merge(headers)
  end

  it "rejects requests without the token" do
    list_tools
    expect(response).to have_http_status(:unauthorized)
    expect(response.headers["WWW-Authenticate"]).to include("Bearer")
  end

  it "rejects a wrong token" do
    list_tools("Authorization" => "Bearer nope")
    expect(response).to have_http_status(:unauthorized)
  end

  it "accepts the right token" do
    list_tools("Authorization" => "Bearer s3cret-token")
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("result", "tools")).to be_present
  end

  it "is open when the token is unset" do
    ENV["MCP_BEARER_TOKEN"] = nil
    list_tools
    expect(response).to have_http_status(:ok)
  end
end
