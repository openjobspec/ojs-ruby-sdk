# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe OJS::Worker do
  let(:logger) { Logger.new(File::NULL) }
  let(:worker) do
    described_class.new(OJS_TEST_BASE_URL,
      queues: %w[default],
      concurrency: 2,
      poll_interval: 0.1,
      heartbeat_interval: 60.0,
      shutdown_timeout: 2.0,
      logger: logger)
  end

  describe "#register" do
    it "registers a handler for a job type" do
      worker.register("email.send") { |ctx| { sent: true } }

      # Handler is stored internally
      expect(worker.instance_variable_get(:@handlers)).to have_key("email.send")
    end

    it "raises without a block" do
      expect { worker.register("email.send") }.to raise_error(ArgumentError)
    end
  end

  describe "#use" do
    it "adds middleware to the chain" do
      worker.use("logging") { |ctx, &nxt| nxt.call }

      expect(worker.middleware.size).to eq(1)
    end
  end

  describe "#state" do
    it "starts as :stopped" do
      expect(worker.state).to eq(:stopped)
    end
  end

  describe "#stop" do
    it "transitions to :terminating from :running" do
      # Simulate running state
      worker.instance_variable_set(:@state, :running)

      worker.stop

      expect(worker.state).to eq(:terminating)
    end

    it "is a no-op when stopped" do
      worker.stop

      expect(worker.state).to eq(:stopped)
    end
  end

  describe "#quiet" do
    it "transitions to :quiet from :running" do
      worker.instance_variable_set(:@state, :running)

      worker.quiet

      expect(worker.state).to eq(:quiet)
    end
  end

  describe "job processing" do
    it "processes a job through handler and middleware" do
      executed = []

      worker.use("test") do |ctx, &nxt|
        executed << :middleware_before
        result = nxt.call
        executed << :middleware_after
        result
      end

      worker.register("test.job") do |ctx|
        executed << :handler
        { done: true }
      end

      # Simulate processing directly
      job = OJS::Job.new(type: "test.job", args: { "key" => "value" })
      ctx = OJS::JobContext.new(job: job, worker: worker)

      # Stub ack
      stub_ojs_post("/workers/ack", status: 200, response_body: {})

      worker.send(:process_job, job)

      expect(executed).to eq([:middleware_before, :handler, :middleware_after])
    end

    it "nacks a job when no handler is registered" do
      stub_nack = stub_ojs_post("/workers/nack", status: 200, response_body: {})

      job = OJS::Job.new(type: "unknown.type", args: {})
      worker.send(:process_job, job)

      expect(stub_nack).to have_been_requested
    end

    it "nacks a job when handler raises an error" do
      worker.register("failing.job") { |ctx| raise "boom" }

      stub_nack = stub_ojs_post("/workers/nack", status: 200, response_body: {})

      job = OJS::Job.new(type: "failing.job", args: {})
      worker.send(:process_job, job)

      expect(stub_nack).to have_been_requested
      expect(WebMock).to have_requested(:post, "#{OJS_TEST_API_BASE}/workers/nack")
        .with { |req|
          body = JSON.parse(req.body)
          body["error"]["type"] == "RuntimeError" &&
            body["error"]["message"] == "boom"
        }
    end
  end

  describe "job context" do
    it "provides access to job args" do
      job = OJS::Job.new(type: "test.job", args: { "key" => "value" })
      ctx = OJS::JobContext.new(job: job, worker: worker)

      expect(ctx.job.args["key"]).to eq("value")
      expect(ctx.job.type).to eq("test.job")
    end

    it "provides a mutable store for middleware data" do
      job = OJS::Job.new(type: "test.job", args: {})
      ctx = OJS::JobContext.new(job: job, worker: worker)

      ctx.store[:trace_id] = "abc-123"

      expect(ctx.store[:trace_id]).to eq("abc-123")
    end
  end

  describe "#logger" do
    it "defaults to a Logger when none provided" do
      w = described_class.new(OJS_TEST_BASE_URL)

      expect(w.logger).to be_a(Logger)
    end

    it "accepts a custom logger" do
      custom_logger = Logger.new(StringIO.new)
      w = described_class.new(OJS_TEST_BASE_URL, logger: custom_logger)

      expect(w.logger).to eq(custom_logger)
    end
  end

  describe "fetch" do
    it "fetches jobs from the server" do
      stub_ojs_post("/workers/fetch", status: 200, response_body: {
        "jobs" => [sample_job_response],
      })

      jobs = worker.send(:fetch_jobs)

      expect(jobs.length).to eq(1)
      expect(jobs[0]).to be_a(OJS::Job)
      expect(jobs[0].type).to eq("email.send")
    end

    it "returns empty array on fetch error" do
      stub_ojs_post("/workers/fetch", status: 500, response_body: {
        "error" => { "code" => "backend_error", "message" => "Redis down" },
      })

      jobs = worker.send(:fetch_jobs)

      expect(jobs).to eq([])
    end
  end
end
