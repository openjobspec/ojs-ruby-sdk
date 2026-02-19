# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module OJS
  module Transport
    # Thin HTTP transport layer using only net/http from the standard library.
    #
    # Uses persistent connections with keep-alive to avoid per-request TCP/TLS
    # handshake overhead. Thread-safe: each thread gets its own connection via
    # Thread.current storage.
    class HTTP
      CONTENT_TYPE = "application/openjobspec+json"
      BASE_PATH = "/ojs/v1"
      USER_AGENT = "ojs-ruby/#{OJS::VERSION} ruby/#{RUBY_VERSION}"

      # @param base_url [String] server base URL (e.g., "http://localhost:8080")
      # @param timeout [Integer] request timeout in seconds
      # @param headers [Hash] additional headers to send with every request
      # @param rate_limiter [RateLimiter, nil] optional rate limiter for automatic 429 retry
      def initialize(base_url, timeout: 30, headers: {}, rate_limiter: nil)
        @uri = URI.parse(base_url.chomp("/"))
        @timeout = timeout
        @extra_headers = headers.transform_keys(&:to_s)
        @connection_key = :"ojs_http_#{object_id}"
        @rate_limiter = rate_limiter
      end

      # POST request, returns parsed JSON body.
      def post(path, body: nil, absolute: false)
        request(Net::HTTP::Post, path, body: body, absolute: absolute)
      end

      # GET request, returns parsed JSON body.
      def get(path, params: {}, absolute: false)
        full_path = path
        unless params.empty?
          query = URI.encode_www_form(params.reject { |_, v| v.nil? })
          full_path = "#{path}?#{query}"
        end
        request(Net::HTTP::Get, full_path, absolute: absolute)
      end

      # DELETE request, returns parsed JSON body.
      def delete(path, absolute: false)
        request(Net::HTTP::Delete, path, absolute: absolute)
      end

      # Close the persistent connection for the current thread.
      def close
        conn = Thread.current[@connection_key]
        if conn
          conn.finish if conn.started?
          Thread.current[@connection_key] = nil
        end
      end

      private

      def request(method_class, path, body: nil, absolute: false)
        full_path = absolute ? path : "#{BASE_PATH}#{path}"
        req = method_class.new(full_path, default_headers)
        req.body = JSON.generate(body) if body

        attempt = 0
        begin
          response = connection.request(req)
          handle_response(response)
        rescue RateLimitError => e
          if @rate_limiter&.should_retry?(attempt)
            duration = @rate_limiter.backoff_duration(attempt, retry_after: e.retry_after)
            @rate_limiter.logger&.info(
              "OJS rate limited, retry #{attempt + 1}/#{@rate_limiter.max_retries} after #{duration.round(2)}s"
            )
            # Thread#raise can interrupt this sleep, which provides
            # cancellation support for threaded callers.
            sleep(duration)
            attempt += 1
            retry
          end
          raise
        rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH,
               Errno::ENETUNREACH, SocketError, IOError, EOFError => e
          # Connection went stale — reset and retry once
          reset_connection
          begin
            response = connection.request(req)
            handle_response(response)
          rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH,
                 Errno::ENETUNREACH, SocketError, IOError, EOFError => e
            reset_connection
            raise ConnectionError.new("Connection to #{@uri.host}:#{@uri.port} failed: #{e.message}")
          end
        rescue Net::OpenTimeout, Net::ReadTimeout => e
          raise TimeoutError.new("Request to #{full_path} timed out: #{e.message}")
        end
      end

      # Returns a persistent Net::HTTP connection for the current thread.
      # Creates a new connection if none exists or the existing one is closed.
      def connection
        conn = Thread.current[@connection_key]
        return conn if conn&.started?

        conn = Net::HTTP.new(@uri.host, @uri.port)
        conn.use_ssl = (@uri.scheme == "https")
        conn.open_timeout = @timeout
        conn.read_timeout = @timeout
        conn.write_timeout = @timeout
        conn.keep_alive_timeout = 30
        conn.start
        Thread.current[@connection_key] = conn
        conn
      end

      def reset_connection
        conn = Thread.current[@connection_key]
        conn&.finish if conn&.started?
      rescue IOError
        # Already closed
      ensure
        Thread.current[@connection_key] = nil
      end

      def default_headers
        {
          "Content-Type" => CONTENT_TYPE,
          "Accept" => CONTENT_TYPE,
          "User-Agent" => USER_AGENT,
          "OJS-Version" => OJS::SPEC_VERSION,
        }.merge(@extra_headers)
      end

      def handle_response(response)
        status = response.code.to_i
        body = parse_body(response, raise_on_error: (200..299).cover?(status))

        case status
        when 200, 201
          body
        when 400
          raise Error.from_response(body, http_status: 400)
        when 404
          raise NotFoundError.new(
            extract_message(body, "Not found"),
            request_id: extract_request_id(body),
            http_status: 404,
          )
        when 409
          err = body.is_a?(Hash) ? (body["error"] || body) : {}
          if err["code"] == "duplicate"
            raise ConflictError.new(
              extract_message(body, "Duplicate job"),
              existing_job_id: err.dig("details", "existing_job_id"),
              request_id: extract_request_id(body),
              http_status: 409,
            )
          end
          raise Error.from_response(body, http_status: 409)
        when 413
          raise PayloadTooLargeError.new(
            extract_message(body, "Envelope too large"),
            request_id: extract_request_id(body),
            http_status: 413,
          )
        when 422
          raise UnsupportedError.new(
            extract_message(body, "Feature not supported"),
            request_id: extract_request_id(body),
            http_status: 422,
          )
        when 429
          retry_after = response["Retry-After"]&.to_i
          rate_limit = parse_rate_limit_headers(response, retry_after)
          raise RateLimitError.new(
            extract_message(body, "Rate limited"),
            retry_after: retry_after,
            rate_limit: rate_limit,
            request_id: extract_request_id(body),
            http_status: 429,
          )
        when 500..599
          raise ServerError.new(
            extract_message(body, "Server error"),
            request_id: extract_request_id(body),
            http_status: response.code.to_i,
          )
        else
          raise Error.new(
            "Unexpected response: #{response.code}",
            http_status: response.code.to_i,
          )
        end
      end

      def parse_body(response, raise_on_error: false)
        return nil if response.body.nil? || response.body.empty?

        JSON.parse(response.body)
      rescue JSON::ParserError => e
        if raise_on_error
          raise Error.new(
            "Invalid JSON in response body: #{e.message}",
            http_status: response.code.to_i,
          )
        end
        nil
      end

      def extract_message(body, default)
        return default unless body.is_a?(Hash)

        body.dig("error", "message") || body["message"] || default
      end

      def extract_request_id(body)
        return nil unless body.is_a?(Hash)

        body.dig("error", "request_id") || body["request_id"]
      end

      def parse_rate_limit_headers(response, retry_after)
        limit_raw = response["X-RateLimit-Limit"]
        remaining_raw = response["X-RateLimit-Remaining"]
        reset_raw = response["X-RateLimit-Reset"]

        return nil if limit_raw.nil? && remaining_raw.nil? && reset_raw.nil? && retry_after.nil?

        RateLimitInfo.new(
          limit: limit_raw&.to_i,
          remaining: remaining_raw&.to_i,
          reset: reset_raw&.to_i,
          retry_after: retry_after,
        )
      end
    end
  end
end
