# frozen_string_literal: true

module OJS
  # Base error for all OJS errors.
  class Error < StandardError
    # @return [String, nil] OJS error code
    attr_reader :code

    # @return [Boolean] whether the operation can be retried
    attr_reader :retryable

    # @return [Hash, nil] additional error details
    attr_reader :details

    # @return [String, nil] server-assigned request ID
    attr_reader :request_id

    # @return [Integer, nil] HTTP status code
    attr_reader :http_status

    def initialize(message = nil, code: nil, retryable: false, details: nil, request_id: nil, http_status: nil)
      @code = code
      @retryable = retryable
      @details = details
      @request_id = request_id
      @http_status = http_status
      super(message)
    end

    def retryable?
      @retryable
    end

    # Build an Error (or subclass) from an HTTP response body hash.
    def self.from_response(body, http_status:)
      err = body.is_a?(Hash) ? (body["error"] || body) : {}
      code = err["code"]
      message = err["message"] || "Unknown error"
      retryable = err["retryable"] || false
      details = err["details"]
      request_id = err["request_id"]

      klass = ERROR_CODE_MAP[code] || Error
      klass.new(message, code: code, retryable: retryable, details: details,
                         request_id: request_id, http_status: http_status)
    end
  end

  # Raised when the server cannot be reached.
  class ConnectionError < Error
    def initialize(message = "Connection failed", **kwargs)
      super(message, retryable: true, **kwargs)
    end
  end

  # Raised when a request times out.
  class TimeoutError < Error
    def initialize(message = "Request timed out", **kwargs)
      super(message, code: "timeout", retryable: true, **kwargs)
    end
  end

  # Raised for invalid request payloads (400).
  class ValidationError < Error
    def initialize(message = "Validation failed", code: "invalid_request", **kwargs)
      super(message, code: code, retryable: false, **kwargs)
    end
  end

  # Raised when a resource is not found (404).
  class NotFoundError < Error
    def initialize(message = "Not found", **kwargs)
      super(message, code: "not_found", retryable: false, **kwargs)
    end
  end

  # Raised on unique constraint violations (409).
  class ConflictError < Error
    # @return [String, nil] the existing job ID that caused the conflict
    attr_reader :existing_job_id

    def initialize(message = "Conflict", existing_job_id: nil, **kwargs)
      @existing_job_id = existing_job_id
      super(message, code: "duplicate", retryable: false, **kwargs)
    end
  end

  # Raised when a queue is paused (409).
  class QueuePausedError < Error
    def initialize(message = "Queue is paused", **kwargs)
      super(message, code: "queue_paused", retryable: true, **kwargs)
    end
  end

  # Raised when rate limited (429).
  class RateLimitError < Error
    # @return [Integer, nil] seconds to wait before retrying
    attr_reader :retry_after

    def initialize(message = "Rate limited", retry_after: nil, **kwargs)
      @retry_after = retry_after
      super(message, code: "rate_limited", retryable: true, **kwargs)
    end
  end

  # Raised on server errors (500).
  class ServerError < Error
    def initialize(message = "Server error", **kwargs)
      super(message, code: "backend_error", retryable: true, **kwargs)
    end
  end

  # Raised when payload exceeds size limit (413).
  class PayloadTooLargeError < Error
    def initialize(message = "Envelope too large", **kwargs)
      super(message, code: "envelope_too_large", retryable: false, **kwargs)
    end
  end

  # Raised when a feature is not supported (422).
  class UnsupportedError < Error
    def initialize(message = "Feature not supported", **kwargs)
      super(message, code: "unsupported", retryable: false, **kwargs)
    end
  end

  # Maps OJS error codes to exception classes.
  ERROR_CODE_MAP = {
    "invalid_request"    => ValidationError,
    "invalid_payload"    => ValidationError,
    "schema_validation"  => ValidationError,
    "not_found"          => NotFoundError,
    "duplicate"          => ConflictError,
    "queue_paused"       => QueuePausedError,
    "rate_limited"       => RateLimitError,
    "backend_error"      => ServerError,
    "timeout"            => TimeoutError,
    "unsupported"        => UnsupportedError,
    "envelope_too_large" => PayloadTooLargeError,
  }.freeze
end
