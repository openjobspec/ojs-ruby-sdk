# frozen_string_literal: true

require "logger"

module OJS
  module Transport
    # Configuration and logic for automatic retry on HTTP 429 (rate limited) responses.
    #
    # When enabled, the transport will sleep and retry requests that receive a 429
    # status code, respecting the server's Retry-After header when present and
    # falling back to exponential backoff with jitter.
    #
    #   limiter = OJS::Transport::RateLimiter.new(max_retries: 5)
    #   transport = OJS::Transport::HTTP.new(url, rate_limiter: limiter)
    #
    class RateLimiter
      DEFAULT_MAX_RETRIES = 3
      DEFAULT_MIN_BACKOFF = 0.5  # seconds
      DEFAULT_MAX_BACKOFF = 30.0 # seconds

      # @return [Integer] maximum number of retry attempts on 429
      attr_reader :max_retries

      # @return [Float] minimum backoff duration in seconds
      attr_reader :min_backoff

      # @return [Float] maximum backoff duration in seconds
      attr_reader :max_backoff

      # @return [Boolean] whether rate limit retries are enabled
      attr_reader :enabled

      # @return [Logger, nil] logger for retry diagnostics
      attr_reader :logger

      # @param max_retries [Integer] maximum retry attempts (default: 3)
      # @param min_backoff [Float] minimum backoff in seconds (default: 0.5)
      # @param max_backoff [Float] maximum backoff in seconds (default: 30.0)
      # @param enabled [Boolean] enable/disable rate limit retries (default: true)
      # @param logger [Logger, nil] logger instance for retry messages
      def initialize(max_retries: DEFAULT_MAX_RETRIES, min_backoff: DEFAULT_MIN_BACKOFF,
                     max_backoff: DEFAULT_MAX_BACKOFF, enabled: true, logger: nil)
        @max_retries = max_retries
        @min_backoff = min_backoff.to_f
        @max_backoff = max_backoff.to_f
        @enabled = enabled
        @logger = logger
      end

      # Calculate the backoff duration for a given retry attempt.
      #
      # If the server provided a Retry-After value, it is used (clamped to max_backoff).
      # Otherwise, exponential backoff with jitter is applied:
      #   sleep = min(max_backoff, min_backoff * 2^attempt) * rand(0.5..1.0)
      #
      # @param attempt [Integer] zero-based retry attempt number
      # @param retry_after [Integer, nil] server-provided Retry-After in seconds
      # @return [Float] seconds to sleep
      def backoff_duration(attempt, retry_after: nil)
        if retry_after && retry_after > 0
          [retry_after.to_f, @max_backoff].min
        else
          base = [@min_backoff * (2**attempt), @max_backoff].min
          base * rand(0.5..1.0)
        end
      end

      # Whether a retry should be attempted.
      #
      # @param attempt [Integer] zero-based retry attempt number
      # @return [Boolean]
      def should_retry?(attempt)
        @enabled && attempt < @max_retries
      end
    end
  end
end
