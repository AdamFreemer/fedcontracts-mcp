# Per-IP throttles. The store is in-process memory: fine for one web dyno; with
# several dynos or Puma workers each keeps its own counts (limits multiply).
class Rack::Attack
  MCP_LIMIT = Integer(ENV.fetch("MCP_RATE_LIMIT_PER_MINUTE", 60))

  self.cache.store = ActiveSupport::Cache::MemoryStore.new

  throttle("mcp/ip", limit: MCP_LIMIT, period: 1.minute) do |req|
    req.ip if req.path == "/mcp" || req.path.start_with?("/mcp/")
  end

  throttle("health/ip", limit: 30, period: 1.minute) do |req|
    req.ip if req.path == "/health/data"
  end

  # JSON-RPC-shaped 429 with Retry-After, so MCP clients get a readable error.
  self.throttled_responder = lambda do |req|
    match = req.env["rack.attack.match_data"] || {}
    retry_after = (match[:period] || 60) - (Time.now.to_i % (match[:period] || 60))
    body = { jsonrpc: "2.0", error: { code: -32029, message: "Rate limit exceeded (#{match[:limit]} requests/minute). Retry after #{retry_after}s." } }
    [ 429, { "content-type" => "application/json", "retry-after" => retry_after.to_s }, [ body.to_json ] ]
  end
end
