module Usaspending
  # Thin HTTP client for the USAspending award search API. No API key needed.
  # Used only by the sync; MCP tools never call this.
  class Client
    BASE_URL = "https://api.usaspending.gov".freeze
    SPENDING_BY_AWARD_PATH = "/api/v2/search/spending_by_award/".freeze
    TOPTIER_AGENCIES_PATH = "/api/v2/references/toptier_agencies/".freeze
    AWARD_PATH = "/api/v2/awards/%s/".freeze
    CONTRACT_AWARD_TYPES = %w[A B C D].freeze
    MAX_LIMIT = 100
    # The API rejects page * limit beyond this; callers must narrow the window.
    MAX_RESULT_WINDOW = 50_000
    SORT_FIELD = "Base Obligation Date".freeze

    FIELDS = [
      "Award ID",
      "generated_internal_id",
      "Recipient Name",
      "recipient_id",
      "Recipient UEI",
      "Recipient Location",
      "Awarding Agency",
      "Awarding Agency Code",
      "Awarding Sub Agency",
      "Description",
      "Award Amount",
      "Start Date",
      "End Date",
      "Base Obligation Date",
      "Last Modified Date",
      "NAICS",
      "PSC",
      "Place of Performance State Code",
      "Contract Award Type"
    ].freeze

    Error = Class.new(StandardError)
    # Raised when USAspending drops or refuses connections, which is how it rate-limits.
    ConnectionRefused = Class.new(Error)
    Page = Data.define(:results, :has_next)

    def initialize(max_retries: 4, retry_interval: 1.0, timeout: 25)
      @max_retries = max_retries
      @retry_interval = retry_interval
      @timeout = timeout
    end

    # Contracts whose latest action date falls in [start_date, end_date]. Using
    # date_type "action_date" makes adjacent windows partition the results exactly,
    # which lets the sync chunk a long range under MAX_RESULT_WINDOW.
    def spending_by_award(start_date:, end_date:, naics_codes:, page: 1, limit: MAX_LIMIT)
      limit = limit.clamp(1, MAX_LIMIT)
      body = {
        filters: {
          award_type_codes: CONTRACT_AWARD_TYPES,
          time_period: [ { start_date: start_date.iso8601, end_date: end_date.iso8601, date_type: "action_date" } ],
          naics_codes: naics_codes
        },
        fields: FIELDS,
        sort: SORT_FIELD,
        order: "desc",
        limit: limit,
        page: page
      }

      response = request { connection.post(SPENDING_BY_AWARD_PATH, body) }
      Page.new(results: response.body.fetch("results"), has_next: response.body.dig("page_metadata", "hasNext") == true)
    rescue KeyError, NoMethodError => e
      raise Error, "Unexpected USAspending response shape: #{e.message}"
    end

    # All toptier agencies: [{ "toptier_code" => "070", "abbreviation" => "DHS", ... }, ...]
    def toptier_agencies
      request { connection.get(TOPTIER_AGENCIES_PATH) }.body.fetch("results")
    rescue KeyError, NoMethodError => e
      raise Error, "Unexpected USAspending response shape: #{e.message}"
    end

    # Full award detail, including period_of_performance.potential_end_date.
    def award(generated_internal_id)
      request { connection.get(format(AWARD_PATH, ERB::Util.url_encode(generated_internal_id))) }.body.to_h
    end

    private

    # Runs a request (retries happen inside the connection) and translates failures.
    def request
      yield
    rescue Faraday::SSLError, Faraday::ConnectionFailed => e
      raise ConnectionRefused, "USAspending refused or dropped the connection (often rate limiting; " \
                               "it clears on its own): #{e.class}: #{e.message}"
    rescue Faraday::Error => e
      raise Error, "USAspending request failed: #{e.class}: #{e.response_status || e.message}"
    end

    def connection
      @connection ||= Faraday.new(url: BASE_URL) do |f|
        f.request :json
        f.request :retry,
          max: @max_retries,
          interval: @retry_interval,
          backoff_factor: 2,
          interval_randomness: 0.5,
          methods: %i[get post],
          retry_statuses: [ 429, 500, 502, 503, 504 ],
          # raise_error turns 429/5xx into these before retry sees the status, so list them too.
          exceptions: Faraday::Retry::Middleware::DEFAULT_EXCEPTIONS +
            [ Faraday::ConnectionFailed, Faraday::SSLError, Faraday::TooManyRequestsError, Faraday::ServerError ]
        f.response :raise_error
        f.response :json
        f.options.timeout = @timeout
        f.options.open_timeout = 10
      end
    end
  end
end
