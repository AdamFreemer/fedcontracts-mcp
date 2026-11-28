require "csv"

module Usaspending
  # USAspending's async bulk award download: request a zip of CSVs, poll until it's
  # generated, download it, and stream the prime contract rows. One request per
  # time window instead of one per award, so it stays well inside USAspending's
  # tolerance for automated clients.
  class BulkDownload
    REQUEST_PATH = "/api/v2/download/awards/".freeze
    CONTRACTS_CSV = /Contracts_PrimeAwardSummaries_.*\.csv\z/
    POLL_INTERVAL = 10 # seconds
    POLL_TIMEOUT = 20 * 60 # seconds; USAspending queues downloads when busy
    MAX_ROWS = 500_000 # API maximum per download

    Error = Class.new(Client::Error)
    TimedOut = Class.new(Error)

    def initialize(poll_interval: POLL_INTERVAL, poll_timeout: POLL_TIMEOUT, logger: Rails.logger, **client_options)
      @poll_interval = poll_interval
      @poll_timeout = poll_timeout
      @logger = logger
      @client_options = client_options
    end

    # Yields each prime contract row (a Hash keyed by CSV header) for contracts whose
    # latest action date falls in [start_date, end_date]. Same filter semantics as
    # Client#spending_by_award, so windows line up with AwardSync.
    def each_contract(start_date:, end_date:, naics_codes:, &block)
      return enum_for(:each_contract, start_date:, end_date:, naics_codes:) unless block

      job = request_download(start_date:, end_date:, naics_codes:)
      file_url = wait_until_ready(job)
      Tempfile.create([ "usaspending", ".zip" ], binmode: true) do |zip_file|
        download(file_url, zip_file)
        each_csv_row(zip_file.path, &block)
      end
    end

    private

    def request_download(start_date:, end_date:, naics_codes:)
      body = {
        filters: {
          prime_award_types: Client::CONTRACT_AWARD_TYPES,
          award_type_codes: Client::CONTRACT_AWARD_TYPES,
          time_period: [ { start_date: start_date.iso8601, end_date: end_date.iso8601, date_type: "action_date" } ],
          naics_codes: { require: naics_codes }
        },
        file_format: "csv",
        limit: MAX_ROWS
      }
      response = guarded { api.post(REQUEST_PATH, body) }
      response.body.slice("status_url", "file_url", "file_name").tap do |job|
        raise Error, "Download request returned no status_url: #{response.body.inspect.truncate(300)}" if job["status_url"].blank?
      end
    end

    def wait_until_ready(job)
      deadline = monotonic_now + @poll_timeout
      loop do
        status = guarded { api.get(job["status_url"]) }.body
        case status["status"]
        when "finished"
          @logger.info("[BulkDownload] #{job['file_name']}: #{status['total_rows']} rows in #{status['seconds_elapsed'].to_f.round}s")
          return status["file_url"].presence || job["file_url"]
        when "failed"
          raise Error, "USAspending failed to generate #{job['file_name']}: #{status['message']}"
        end
        raise TimedOut, "#{job['file_name']} not ready after #{@poll_timeout}s (status: #{status['status']})" if monotonic_now >= deadline

        sleep(@poll_interval)
      end
    end

    def download(file_url, file)
      guarded do
        files.get(file_url) do |req|
          req.options.on_data = proc { |chunk, _received| file.write(chunk) }
        end
      end
      file.flush
    end

    def each_csv_row(zip_path)
      Zip::File.open(zip_path) do |zip|
        entries = zip.entries.select { |e| e.name.match?(CONTRACTS_CSV) }.sort_by(&:name) # large downloads split into _1, _2, ...
        raise Error, "No prime contracts CSV in download (#{zip.entries.map(&:name).join(', ')})" if entries.empty?

        entries.each do |entry|
          entry.get_input_stream do |io|
            CSV.new(io, headers: true).each { |row| yield row.to_h }
          end
        end
      end
    end

    def guarded
      yield
    rescue Faraday::SSLError, Faraday::ConnectionFailed => e
      raise Client::ConnectionRefused, "USAspending refused or dropped the connection (often rate limiting; " \
                                       "it clears on its own): #{e.class}: #{e.message}"
    rescue Faraday::Error => e
      raise Error, "USAspending download failed: #{e.class}: #{e.response_status || e.message}"
    end

    def api
      @api ||= Client.new(**@client_options).connection
    end

    # Plain connection for the zip (files.usaspending.gov), no JSON parsing.
    def files
      @files ||= Faraday.new do |f|
        f.request :retry, max: 3, interval: 2, backoff_factor: 2, methods: %i[get],
                          exceptions: Faraday::Retry::Middleware::DEFAULT_EXCEPTIONS + [ Faraday::ConnectionFailed, Faraday::SSLError ]
        f.response :raise_error
        f.options.timeout = 300
        f.options.open_timeout = 10
      end
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
