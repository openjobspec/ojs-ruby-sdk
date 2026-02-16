# frozen_string_literal: true

require_relative "spec_helper"
require "ojs/middleware/logging"
require "ojs/middleware/timeout"
require "ojs/middleware/retry"
require "ojs/middleware/metrics"

RSpec.describe "Common Middleware Implementations" do
  let(:job) do
    OJS::Job.new(type: "test.job", args: {}, id: "test-id", queue: "default", attempt: 1)
  end
  let(:worker) { instance_double(OJS::Worker) }
  let(:ctx) { OJS::JobContext.new(job: job, worker: worker) }

  describe OJS::Middleware::Logging do
    let(:logger) { instance_double(Logger) }
    let(:middleware) { described_class.new(logger: logger) }

    before do
      allow(logger).to receive(:debug)
      allow(logger).to receive(:info)
      allow(logger).to receive(:error)
    end

    it "logs completion on success" do
      middleware.call(ctx) { "ok" }

      expect(logger).to have_received(:info).with(/Job completed/)
    end

    it "logs failure on error" do
      expect {
        middleware.call(ctx) { raise RuntimeError, "boom" }
      }.to raise_error(RuntimeError, "boom")

      expect(logger).to have_received(:error).with(/Job failed/)
    end
  end

  describe OJS::Middleware::Timeout do
    it "passes when job completes in time" do
      mw = described_class.new(seconds: 5)
      result = mw.call(ctx) { "ok" }
      expect(result).to eq("ok")
    end

    it "raises TimeoutError when job exceeds timeout" do
      mw = described_class.new(seconds: 0.01)
      expect {
        mw.call(ctx) { sleep(1) }
      }.to raise_error(OJS::Middleware::Timeout::TimeoutError)
    end
  end

  describe OJS::Middleware::Retry do
    it "passes on success" do
      mw = described_class.new(max_retries: 3, base_delay: 0.001)
      result = mw.call(ctx) { "ok" }
      expect(result).to eq("ok")
    end

    it "retries and succeeds" do
      mw = described_class.new(max_retries: 3, base_delay: 0.001, jitter: false)
      calls = 0
      result = mw.call(ctx) do
        calls += 1
        raise RuntimeError, "fail" if calls < 3

        "ok"
      end

      expect(result).to eq("ok")
      expect(calls).to eq(3)
    end

    it "raises after exhausting retries" do
      mw = described_class.new(max_retries: 2, base_delay: 0.001, jitter: false)
      expect {
        mw.call(ctx) { raise RuntimeError, "always fails" }
      }.to raise_error(RuntimeError, "always fails")
    end
  end

  describe OJS::Middleware::Metrics do
    let(:recorder) do
      Class.new do
        include OJS::Middleware::MetricsRecorder

        attr_reader :started, :completed, :failed

        def initialize
          @started = 0
          @completed = 0
          @failed = 0
        end

        def job_started(_job_type, _queue)
          @started += 1
        end

        def job_completed(_job_type, _queue, _duration_s)
          @completed += 1
        end

        def job_failed(_job_type, _queue, _duration_s, _error)
          @failed += 1
        end
      end.new
    end

    let(:middleware) { described_class.new(recorder: recorder) }

    it "records completion on success" do
      middleware.call(ctx) { "ok" }

      expect(recorder.started).to eq(1)
      expect(recorder.completed).to eq(1)
      expect(recorder.failed).to eq(0)
    end

    it "records failure on error" do
      expect {
        middleware.call(ctx) { raise RuntimeError, "boom" }
      }.to raise_error(RuntimeError)

      expect(recorder.started).to eq(1)
      expect(recorder.failed).to eq(1)
      expect(recorder.completed).to eq(0)
    end
  end
end
