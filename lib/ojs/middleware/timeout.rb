# frozen_string_literal: true

require "timeout"

module OJS
  module Middleware
    # Timeout middleware for OJS job processing.
    #
    # Aborts job execution if it exceeds the configured timeout using
    # Ruby's +Timeout.timeout+.
    #
    # @example
    #   worker.middleware.add(:timeout, &OJS::Middleware::Timeout.new(seconds: 30).method(:call))
    #
    class Timeout
      # Error raised when a job exceeds its execution timeout.
      class TimeoutError < ::Timeout::Error
        # @return [Float] the configured timeout in seconds
        attr_reader :timeout_seconds

        # @return [String, nil] the ID of the job that timed out
        attr_reader :job_id

        def initialize(timeout_seconds:, job_id:)
          @timeout_seconds = timeout_seconds
          @job_id = job_id
          super("Job #{job_id} timed out after #{timeout_seconds}s")
        end
      end

      # @param seconds [Numeric] maximum execution time in seconds
      def initialize(seconds:)
        @seconds = seconds
      end

      # Middleware entry point.
      #
      # @param ctx [OJS::JobContext] the job context
      # @yield continues the middleware chain
      # @return [Object] the job result
      # @raise [TimeoutError] if the job exceeds the timeout
      def call(ctx, &next_handler)
        ::Timeout.timeout(@seconds, TimeoutError.new(timeout_seconds: @seconds, job_id: ctx.job.id)) do
          next_handler.call
        end
      end
    end
  end
end
