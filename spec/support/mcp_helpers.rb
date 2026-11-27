module McpHelpers
  MCP_HEADERS = { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json, text/event-stream" }.freeze

  # POSTs a JSON-RPC request to /mcp and returns the parsed response body.
  def mcp_request(method, params = nil, id: 1)
    body = { jsonrpc: "2.0", id:, method:, params: }.compact
    post "/mcp", params: body.to_json, headers: MCP_HEADERS
    JSON.parse(response.body)
  end

  def call_tool(name, arguments = {})
    mcp_request("tools/call", { name:, arguments: }).fetch("result")
  end
end

RSpec.configure do |config|
  config.include McpHelpers, type: :request
  # The transport's DNS-rebinding check allows loopback hosts only (plus MCP_ALLOWED_HOSTS).
  config.before(type: :request) { host! "localhost" }
end
