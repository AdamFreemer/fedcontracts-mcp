# The public landing page at /. The rest of the app is API-only; this one
# controller renders HTML, so it inherits ActionController::Base.
class PagesController < ActionController::Base
  def home
    @mcp_url = "#{request.base_url}/mcp"
    @tools = McpEndpoint::TOOLS
    health = DataHealth.new
    @report = health.report
    @runs = health.recent_runs
  end
end
