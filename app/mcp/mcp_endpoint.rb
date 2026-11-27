# Rack app mounted at /mcp. Stateless Streamable HTTP with plain JSON responses:
# every POST is self-contained (no sessions, no SSE), which keeps each call short
# and well under Heroku's 30s router timeout.
#
# A fresh server and transport per request keeps this stateless and safe under
# code reloading in development; construction is cheap.
class McpEndpoint
  TOOLS = [ Tools::SearchAwards, Tools::RecentAwards, Tools::ExpiringContracts, Tools::CompanyProfile ].freeze

  INSTRUCTIONS = <<~TEXT.freeze
    Federal contract awards from USAspending.gov, focused on IT and software
    (NAICS 541511, 541512, 541513, 541519, 518210). Use it to find who is winning
    government tech work, which agencies are buying, and which contracts are
    ending soon: signals for hiring, teaming, and market research. Data is
    synced daily from USAspending into this server's database and covers prime
    contracts with activity in about the last 2 years; every response includes
    data_freshness. Department of Defense data publishes with a ~90 day delay, so
    recent DoD activity is sparse. Prime contracts only: subcontractors, who do
    much of the hiring on large programs, are not included.
  TEXT

  # Bodies here are small JSON-RPC calls; reject anything bigger early.
  MAX_REQUEST_BYTES = 64 * 1024

  def self.call(env)
    return unauthorized unless authorized?(env)

    transport.call(env)
  end

  # Optional shared secret. When MCP_BEARER_TOKEN is set, every request must send
  # `Authorization: Bearer <token>`. Unset (the public demo), the endpoint is open.
  def self.authorized?(env)
    token = ENV["MCP_BEARER_TOKEN"].to_s
    return true if token.empty?

    header = env["HTTP_AUTHORIZATION"].to_s
    provided = header.start_with?("Bearer ") ? header.delete_prefix("Bearer ") : ""
    ActiveSupport::SecurityUtils.secure_compare(provided, token)
  end

  def self.unauthorized
    body = { jsonrpc: "2.0", error: { code: -32001, message: "Unauthorized: send Authorization: Bearer <token>" } }.to_json
    [ 401, { "content-type" => "application/json", "www-authenticate" => 'Bearer realm="fedcontracts"' }, [ body ] ]
  end

  def self.server
    MCP::Server.new(
      name: "fedcontracts",
      title: "FedContracts",
      version: Fedcontracts::VERSION,
      instructions: INSTRUCTIONS,
      tools: TOOLS,
      configuration: MCP::Configuration.new(exception_reporter: method(:report_exception))
    )
  end

  def self.transport
    MCP::Server::Transports::StreamableHTTPTransport.new(
      server,
      stateless: true,
      enable_json_response: true,
      serve_subscriptions_listen: false,
      allowed_hosts: allowed_hosts,
      max_request_bytes: MAX_REQUEST_BYTES
    )
  end

  # Host-header (DNS rebinding) protection stays on. Loopback is allowed by
  # default; deployed hostnames come from MCP_ALLOWED_HOSTS (comma-separated).
  def self.allowed_hosts
    ENV.fetch("MCP_ALLOWED_HOSTS", "").split(",").map(&:strip).reject(&:empty?)
  end

  # The SDK already hides exception details from clients; this makes sure we see them.
  def self.report_exception(exception, context)
    Rails.error.report(exception, handled: true, context: { mcp: context.inspect.truncate(500) })
    Rails.logger.error("[MCP] #{exception.class}: #{exception.message}")
  end
end
