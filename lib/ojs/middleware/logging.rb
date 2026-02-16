# frozen_string_literal: true

require "logger"

module OJS
  module Middleware
    # Logging middleware for OJS job processing.
    #
    # Logs job start, completion, and failure events with timing information
    # using Ruby's standard +Logger+.
    #
    # @example
    #   worker.middleware.add(:logging, &OJS::Middleware::Logging.new.method(:call))
    #
    # @example With a custom logger
    #   logger = Logger.new($stdout, level: Logger::DEBUG)
    #   worker.middleware.add(:logging, &OJS::Middleware::Logging.new(logger: logger).method(:call))
    #
    class Logging
      # @param logger [Logger] the logger instance. Defaults to a new Logger on STDOUT.
      def initialize(logger: Logger.new($stdout))
        @logger = logger
      end

      # Middleware entry point.
      #
      # @param ctx [OJS::JobContext] the job context
      # @yield continues the middleware chain
      # @return [Object] the job result
      def call(ctx, &next_handler)
        job = ctx.job
        @logger.debug("Job started: #{job.type} (id=#{job.id}, attempt=#{job.attempt})")

        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        begin
          result = next_handler.call
          duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)
          @logger.info("Job completed: #{job.type} (id=#{job.id}, #{duration_ms}ms)")
          result
        rescue StandardError => e
          duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)
          @logger.error("Job failed: #{job.type} (id=#{job.id}, #{duration_ms}ms): #{e.message}")
          raise
        end
      end
    end
  end
end
