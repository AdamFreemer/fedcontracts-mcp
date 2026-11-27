# GET /health/data: 200 when award data is fresh, 503 when stale or never synced.
# Point an external uptime monitor here; it alerts when good news stops arriving,
# whatever the cause (USAspending blocking us, a broken deploy, a missed schedule).
class HealthController < ApplicationController
  def data
    health = DataHealth.new
    render json: health.report, status: health.healthy? ? :ok : :service_unavailable
  end
end
