# frozen_string_literal: true

module OJS
  module Middleware
    # Retry middleware for OJS job processing.
    #
    # Retries failed job executions with configurable exponential backoff
    # and optional jitter.
    #
    # @example
    #   worker.middleware.add(:retry, &OJS::Middleware::Retry.new(max_retries: 3).method(:call))
    #
    class Retry
      # @param max_retries [Integer] maximum number of retry attempts (default: 3)
      # @param base_delay [Float] base delay in seconds for exponential backoff (default: 0.1)
      # @param max_delay [Float] maximum delay in seconds (default: 30.0)
      # @param jitter [Boolean] whether to add random jitter (default: true)
      def initialize(max_retries: 3, base_delay: 0.1, max_delay: 30.0, jitter: true)
        @max_retries = max_retries
        @base_delay = base_delay
        @max_delay = max_delay
        @jitter = jitter
      end

      # Middleware entry point.
      #
      # @param ctx [OJS::JobContext] the job context
      # @yield continues the middleware chain
      # @return [Object] the job result
      # @raise [StandardError] the last error if all retries are exhausted
      def call(ctx, &next_handler)
        last_error = nil

        (@max_retries + 1).times do |attempt|
          begin
            return next_handler.call
          rescue StandardError => e
            last_error = e
            break if attempt >= @max_retries

            exponential_delay = @base_delay * (2**attempt)
            capped_delay = [exponential_delay, @max_delay].min
            final_delay = @jitter ? capped_delay * (0.5 + rand * 0.5) : capped_delay
            sleep(final_delay)
          end
        end

        raise last_error
      end
    end
  end
end
