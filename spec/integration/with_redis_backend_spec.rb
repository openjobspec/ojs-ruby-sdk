# frozen_string_literal: true

require_relative "../spec_helper"

# Integration tests against a running OJS server with a Redis backend.
#
# These tests are skipped by default. To run them:
#
#   OJS_INTEGRATION=1 OJS_URL=http://localhost:8080 bundle exec rspec spec/integration/
#
# Prerequisites:
#   - An OJS-compatible server running with a Redis backend
#   - Server URL in OJS_URL (defaults to http://localhost:8080)
#
RSpec.describe "Integration: Redis backend", skip: !ENV["OJS_INTEGRATION"] do
  let(:base_url) { ENV.fetch("OJS_URL", "http://localhost:8080") }
  let(:client) { OJS::Client.new(base_url) }
  let(:test_queue) { "integration-test-#{SecureRandom.hex(4)}" }

  describe "health check" do
    it "reports healthy status" do
      health = client.health

      expect(health["status"]).to eq("ok")
      expect(health["version"]).to eq(OJS::SPEC_VERSION)
    end
  end

  describe "job lifecycle" do
    it "enqueues and retrieves a job" do
      job = client.enqueue("integration.test",
        { test_id: SecureRandom.hex(8), timestamp: Time.now.utc.iso8601 },
        queue: test_queue
      )

      expect(job.id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/)
      expect(job.type).to eq("integration.test")

      fetched = client.get_job(job.id)
      expect(fetched.id).to eq(job.id)
      expect(fetched.type).to eq("integration.test")
    end

    it "cancels a job" do
      job = client.enqueue("integration.cancel_test",
        { test: true },
        queue: test_queue
      )

      client.cancel_job(job.id)

      fetched = client.get_job(job.id)
      expect(fetched.state).to eq("cancelled")
    end
  end

  describe "batch enqueue" do
    it "enqueues multiple jobs atomically" do
      jobs = client.enqueue_batch(
        5.times.map { |i|
          { type: "integration.batch_test", args: { index: i }, queue: test_queue }
        }
      )

      expect(jobs.length).to eq(5)
      jobs.each { |j| expect(j.type).to eq("integration.batch_test") }
    end
  end

  describe "queue operations" do
    it "shows queue stats" do
      # Enqueue a job to ensure the queue exists
      client.enqueue("integration.stats_test", { test: true }, queue: test_queue)

      stats = client.queue_stats(test_queue)

      expect(stats.name).to eq(test_queue)
      expect(stats.depth).to be >= 1
    end

    it "pauses and resumes a queue" do
      client.enqueue("integration.pause_test", { test: true }, queue: test_queue)

      client.pause_queue(test_queue)
      stats = client.queue_stats(test_queue)
      expect(stats.paused?).to be true

      client.resume_queue(test_queue)
      stats = client.queue_stats(test_queue)
      expect(stats.paused?).to be false
    end
  end

  describe "unique jobs" do
    it "rejects duplicate jobs" do
      unique = OJS::UniquePolicy.new(
        keys: ["type", "args"],
        period: "PT1M",
        on_conflict: "reject"
      )

      args = { unique_test_id: SecureRandom.hex(8) }

      # First enqueue succeeds
      job1 = client.enqueue("integration.unique_test", args,
        queue: test_queue, unique: unique)
      expect(job1.id).not_to be_nil

      # Second enqueue should be rejected
      expect {
        client.enqueue("integration.unique_test", args,
          queue: test_queue, unique: unique)
      }.to raise_error(OJS::ConflictError)
    end
  end

  describe "worker round-trip" do
    it "fetches, processes, and acks a job" do
      # Enqueue
      client.enqueue("integration.worker_test",
        { message: "hello" },
        queue: test_queue
      )

      # Create a worker and process one job
      worker = OJS::Worker.new(base_url,
        queues: [test_queue],
        concurrency: 1,
        poll_interval: 0.5,
        shutdown_timeout: 5.0
      )

      result_received = nil

      worker.register("integration.worker_test") do |ctx|
        result_received = ctx.job.args["message"]
        { processed: true }
      end

      # Start worker in a thread, let it process one job, then stop
      worker_thread = Thread.new { worker.start }
      sleep(3) # Give time to fetch and process
      worker.stop
      worker_thread.join(5)

      expect(result_received).to eq("hello")
    end
  end

  describe "workflow" do
    it "creates a chain workflow" do
      result = client.workflow(OJS.chain(
        OJS::Step.new(type: "integration.chain_step1", args: { step: 1 }),
        OJS::Step.new(type: "integration.chain_step2", args: { step: 2 }),
        name: "integration-chain-test"
      ))

      expect(result["id"]).not_to be_nil
    end
  end
end
