# frozen_string_literal: true

module OJS
  # OpenTelemetry middleware for the OJS Ruby SDK.
  #
  # Instruments job processing with OpenTelemetry traces and metrics,
  # following the OJS Observability spec.
  #
  # @example
  #   require "ojs/otel"
  #   require "opentelemetry-api"
  #
  #   worker = OJS::Worker.new(url: "http://localhost:8080", queues: ["default"])
  #   worker.middleware.add(:opentelemetry, &OJS::OpenTelemetryMiddleware.new.method(:call))
  #
  # Prerequisites:
  #   gem install opentelemetry-api
  #
  # @see spec/ojs-observability.md
  class OpenTelemetryMiddleware
    INSTRUMENTATION_NAME = "ojs-ruby-sdk"

    # @param tracer_provider [OpenTelemetry::Trace::TracerProvider, nil]
    #   Custom tracer provider. Defaults to global.
    # @param meter_provider [Object, nil]
    #   Custom meter provider. Defaults to global (when available).
    def initialize(tracer_provider: nil, meter_provider: nil)
      @tracer_provider = tracer_provider
      @meter_provider = meter_provider
    end

    # Middleware entry point. Wraps job execution with an OTel span
    # and records metrics.
    #
    # @param ctx [OJS::JobContext] the job context
    # @yield continues the middleware chain
    # @return [Object] the job result
    def call(ctx, &next_handler)
      tracer = resolve_tracer
      job = ctx.job

      attributes = {
        "messaging.system" => "ojs",
        "messaging.operation" => "process",
        "ojs.job.type" => job.type,
        "ojs.job.id" => job.id,
        "ojs.job.queue" => job.queue,
        "ojs.job.attempt" => job.attempt
      }

      if tracer
        tracer.in_span("process #{job.type}", attributes: attributes, kind: :consumer) do |span|
          execute_with_span(ctx, span, &next_handler)
        end
      else
        # Fallback: execute without tracing (metrics only if available)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        begin
          result = next_handler.call
          duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
          record_completed(job.type, job.queue, duration)
          result
        rescue StandardError => e
          duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
          record_failed(job.type, job.queue, duration)
          raise
        end
      end
    end

    private

    def execute_with_span(ctx, span, &next_handler)
      job = ctx.job
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      begin
        result = next_handler.call
        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

        span.status = OpenTelemetry::Trace::Status.ok if defined?(OpenTelemetry)
        record_completed(job.type, job.queue, duration)
        result
      rescue StandardError => e
        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

        span.record_exception(e) if span.respond_to?(:record_exception)
        if defined?(OpenTelemetry)
          span.status = OpenTelemetry::Trace::Status.error(e.message)
        end
        record_failed(job.type, job.queue, duration)
        raise
      end
    end

    def resolve_tracer
      return nil unless otel_available?

      provider = @tracer_provider || OpenTelemetry.tracer_provider
      provider.tracer(INSTRUMENTATION_NAME)
    rescue StandardError
      nil
    end

    def otel_available?
      defined?(OpenTelemetry) && OpenTelemetry.respond_to?(:tracer_provider)
    end

    def record_completed(job_type, queue, duration)
      # Metrics recording when OpenTelemetry Metrics API is available
      # This is a no-op placeholder until the Ruby OTel Metrics API stabilizes
    end

    def record_failed(job_type, queue, duration)
      # Metrics recording when OpenTelemetry Metrics API is available
    end
  end
end
