# frozen_string_literal: true

module OJS
  module Middleware
    # Abstract metrics recorder interface for OJS job processing.
    #
    # Implement this module's methods to forward job metrics to
    # Prometheus, StatsD, Datadog, or any other metrics system.
    #
    # @example
    #   class MyRecorder
    #     include OJS::Middleware::MetricsRecorder
    #
    #     def job_started(job_type, queue); end
    #     def job_completed(job_type, queue, duration_s); end
    #     def job_failed(job_type, queue, duration_s, error); end
    #   end
    #
    #   worker.middleware.add(:metrics, &OJS::Middleware::Metrics.new(recorder: MyRecorder.new).method(:call))
    #
    module MetricsRecorder
      # Called when a job starts processing.
      # @param job_type [String]
      # @param queue [String]
      def job_started(job_type, queue)
        raise NotImplementedError
      end

      # Called when a job completes successfully.
      # @param job_type [String]
      # @param queue [String]
      # @param duration_s [Float] execution duration in seconds
      def job_completed(job_type, queue, duration_s)
        raise NotImplementedError
      end

      # Called when a job fails with an error.
      # @param job_type [String]
      # @param queue [String]
      # @param duration_s [Float] execution duration in seconds
      # @param error [StandardError] the error that caused the failure
      def job_failed(job_type, queue, duration_s, error)
        raise NotImplementedError
      end
    end

    # Metrics middleware for OJS job processing.
    #
    # Records job execution metrics via a {MetricsRecorder} implementation.
    #
    # @example
    #   recorder = MyRecorder.new
    #   worker.middleware.add(:metrics, &OJS::Middleware::Metrics.new(recorder: recorder).method(:call))
    #
    class Metrics
      # @param recorder [#job_started, #job_completed, #job_failed] a metrics recorder
      def initialize(recorder:)
        @recorder = recorder
      end

      # Middleware entry point.
      #
      # @param ctx [OJS::JobContext] the job context
      # @yield continues the middleware chain
      # @return [Object] the job result
      def call(ctx, &next_handler)
        job = ctx.job
        @recorder.job_started(job.type, job.queue)

        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        begin
          result = next_handler.call
          duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
          @recorder.job_completed(job.type, job.queue, duration)
          result
        rescue StandardError => e
          duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
          @recorder.job_failed(job.type, job.queue, duration, e)
          raise
        end
      end
    end
  end
end
