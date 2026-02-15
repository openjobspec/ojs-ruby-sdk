# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe OJS::Client do
  let(:client) { described_class.new(base_url) }

  describe "#enqueue" do
    it "enqueues a job with keyword args as payload" do
      stub_ojs_post("/jobs", status: 201, response_body: sample_job_response)

      job = client.enqueue("email.send", to: "user@example.com")

      expect(job).to be_a(OJS::Job)
      expect(job.id).to eq("019461a8-1a2b-7c3d-8e4f-5a6b7c8d9e0f")
      expect(job.type).to eq("email.send")
      expect(job.args).to eq({ "to" => "user@example.com" })
    end

    it "enqueues a job with explicit args hash and options" do
      stub_ojs_post("/jobs", status: 201, response_body: sample_job_response(
        "queue" => "reports",
        "args" => [{ "id" => 42 }],
        "type" => "report.generate"
      ))

      job = client.enqueue("report.generate", { id: 42 }, queue: "reports")

      expect(job.type).to eq("report.generate")
      expect(job.args).to eq({ "id" => 42 })
    end

    it "sends correct wire format with args wrapped in array" do
      stub = stub_ojs_post("/jobs", status: 201, response_body: sample_job_response)

      client.enqueue("email.send", to: "user@example.com")

      expect(stub).to have_been_requested
      expect(WebMock).to have_requested(:post, "#{api_base}/jobs")
        .with { |req|
          body = JSON.parse(req.body)
          body["args"] == [{ "to" => "user@example.com" }] &&
            body["type"] == "email.send" &&
            body["specversion"] == OJS::SPEC_VERSION
        }
    end

    it "includes retry policy in wire format" do
      stub_ojs_post("/jobs", status: 201, response_body: sample_job_response)

      client.enqueue("email.send", { to: "test@example.com" },
        retry: OJS::RetryPolicy.new(max_attempts: 5))

      expect(WebMock).to have_requested(:post, "#{api_base}/jobs")
        .with { |req|
          body = JSON.parse(req.body)
          body["retry"]["max_attempts"] == 5
        }
    end

    it "includes unique policy in wire format" do
      stub_ojs_post("/jobs", status: 201, response_body: sample_job_response)

      client.enqueue("email.send", { to: "test@example.com" },
        unique: OJS::UniquePolicy.new(keys: ["type", "args"], period: "PT1H"))

      expect(WebMock).to have_requested(:post, "#{api_base}/jobs")
        .with { |req|
          body = JSON.parse(req.body)
          body["unique"]["keys"] == ["type", "args"] &&
            body["unique"]["period"] == "PT1H"
        }
    end

    it "converts delay to scheduled_at" do
      stub_ojs_post("/jobs", status: 201, response_body: sample_job_response)

      client.enqueue("email.send", { to: "test@example.com" }, delay: "5m")

      expect(WebMock).to have_requested(:post, "#{api_base}/jobs")
        .with { |req|
          body = JSON.parse(req.body)
          # scheduled_at should be ~5 minutes from now
          scheduled = Time.parse(body["scheduled_at"])
          (scheduled - Time.now.utc).between?(290, 310)
        }
    end

    it "raises ConflictError on duplicate job" do
      stub_ojs_post("/jobs", status: 409, response_body: {
        "error" => {
          "code" => "duplicate",
          "message" => "Job already exists",
          "details" => { "existing_job_id" => "existing-123" },
        },
      })

      expect {
        client.enqueue("email.send", to: "user@example.com")
      }.to raise_error(OJS::ConflictError) { |e|
        expect(e.existing_job_id).to eq("existing-123")
        expect(e.retryable?).to be false
      }
    end

    it "raises RateLimitError on 429" do
      stub_request(:post, "#{api_base}/jobs")
        .to_return(
          status: 429,
          body: { "error" => { "code" => "rate_limited", "message" => "Slow down" } }.to_json,
          headers: { "Content-Type" => OJS_TEST_CONTENT_TYPE, "Retry-After" => "30" }
        )

      expect {
        client.enqueue("email.send", to: "user@example.com")
      }.to raise_error(OJS::RateLimitError) { |e|
        expect(e.retry_after).to eq(30)
        expect(e.retryable?).to be true
      }
    end

    it "raises ServerError on 500" do
      stub_ojs_post("/jobs", status: 500, response_body: {
        "error" => { "code" => "backend_error", "message" => "Redis down" },
      })

      expect {
        client.enqueue("email.send", to: "user@example.com")
      }.to raise_error(OJS::ServerError) { |e|
        expect(e.retryable?).to be true
      }
    end
  end

  describe "#enqueue_batch" do
    it "enqueues multiple jobs" do
      stub_ojs_post("/jobs/batch", status: 201, response_body: {
        "jobs" => [
          sample_job_response("id" => "job-1", "args" => [{ "to" => "a@b.com" }]),
          sample_job_response("id" => "job-2", "args" => [{ "to" => "c@d.com" }]),
        ],
      })

      jobs = client.enqueue_batch([
        { type: "email.send", args: { to: "a@b.com" } },
        { type: "email.send", args: { to: "c@d.com" } },
      ])

      expect(jobs.length).to eq(2)
      expect(jobs[0].id).to eq("job-1")
      expect(jobs[1].id).to eq("job-2")
    end
  end

  describe "#workflow" do
    it "creates a chain workflow" do
      stub_ojs_post("/workflows", status: 201, response_body: {
        "id" => "wf-123",
        "type" => "chain",
        "state" => "running",
      })

      result = client.workflow(OJS.chain(
        OJS::Step.new(type: "step.one", args: { a: 1 }),
        OJS::Step.new(type: "step.two", args: { b: 2 }),
        name: "test-chain"
      ))

      expect(result["id"]).to eq("wf-123")

      expect(WebMock).to have_requested(:post, "#{api_base}/workflows")
        .with { |req|
          body = JSON.parse(req.body)
          body["type"] == "chain" &&
            body["name"] == "test-chain" &&
            body["steps"].length == 2
        }
    end

    it "creates a batch workflow with callbacks" do
      stub_ojs_post("/workflows", status: 201, response_body: {
        "id" => "wf-456",
        "type" => "batch",
        "state" => "running",
      })

      result = client.workflow(OJS.batch(
        [OJS::Step.new(type: "email.send", args: { to: "a@b.com" })],
        name: "bulk-send",
        on_complete: OJS::Step.new(type: "batch.done", args: {})
      ))

      expect(result["id"]).to eq("wf-456")

      expect(WebMock).to have_requested(:post, "#{api_base}/workflows")
        .with { |req|
          body = JSON.parse(req.body)
          body["type"] == "batch" &&
            body["callbacks"]["on_complete"]["type"] == "batch.done"
        }
    end
  end

  describe "#get_job" do
    it "fetches a job by ID" do
      stub_ojs_get("/jobs/job-123", response_body: sample_job_response(
        "id" => "job-123", "state" => "completed"
      ))

      job = client.get_job("job-123")

      expect(job.id).to eq("job-123")
      expect(job.state).to eq("completed")
    end

    it "raises NotFoundError for missing job" do
      stub_ojs_get("/jobs/missing", status: 404, response_body: {
        "error" => { "code" => "not_found", "message" => "Job not found" },
      })

      expect { client.get_job("missing") }.to raise_error(OJS::NotFoundError)
    end
  end

  describe "#cancel_job" do
    it "cancels a job" do
      stub_ojs_delete("/jobs/job-123", response_body: { "status" => "cancelled" })

      result = client.cancel_job("job-123")

      expect(result["status"]).to eq("cancelled")
    end
  end

  describe "queue operations" do
    it "lists queues" do
      stub_ojs_get("/queues", response_body: { "queues" => %w[default email reports] })

      result = client.queues

      expect(result).to eq(%w[default email reports])
    end

    it "gets queue stats" do
      stub_ojs_get("/queues/email/stats", response_body: {
        "queue" => "email",
        "depth" => 42,
        "active" => 5,
        "paused" => false,
      })

      stats = client.queue_stats("email")

      expect(stats).to be_a(OJS::QueueStats)
      expect(stats.name).to eq("email")
      expect(stats.depth).to eq(42)
      expect(stats.active).to eq(5)
      expect(stats.paused?).to be false
    end

    it "pauses a queue" do
      stub_ojs_post("/queues/email/pause", status: 200, response_body: {})

      expect { client.pause_queue("email") }.not_to raise_error
    end

    it "resumes a queue" do
      stub_ojs_post("/queues/email/resume", status: 200, response_body: {})

      expect { client.resume_queue("email") }.not_to raise_error
    end
  end

  describe "dead letter operations" do
    it "lists dead letter jobs" do
      stub_ojs_get("/dead-letter", response_body: {
        "jobs" => [sample_job_response("state" => "discarded")],
      })

      jobs = client.dead_letter_jobs

      expect(jobs.length).to eq(1)
      expect(jobs[0].state).to eq("discarded")
    end

    it "retries a dead letter job" do
      stub_ojs_post("/dead-letter/job-123/retry", status: 200,
                     response_body: sample_job_response("id" => "job-456", "state" => "available"))

      job = client.retry_dead_letter("job-123")

      expect(job.id).to eq("job-456")
    end
  end

  describe "#health" do
    it "returns health status" do
      stub_ojs_get("/health", response_body: { "status" => "ok", "version" => OJS::SPEC_VERSION })

      health = client.health

      expect(health["status"]).to eq("ok")
    end
  end

  describe "#close" do
    it "delegates to transport close" do
      transport = instance_double(OJS::Transport::HTTP)
      allow(transport).to receive(:close)
      client_with_transport = described_class.new(base_url, transport: transport)

      client_with_transport.close

      expect(transport).to have_received(:close)
    end
  end

  describe "custom transport" do
    it "uses injected transport instead of HTTP" do
      fake_transport = instance_double(OJS::Transport::HTTP)
      allow(fake_transport).to receive(:post).and_return(sample_job_response)
      allow(fake_transport).to receive(:close)

      custom_client = described_class.new("http://unused", transport: fake_transport)
      job = custom_client.enqueue("email.send", to: "user@example.com")

      expect(job).to be_a(OJS::Job)
      expect(fake_transport).to have_received(:post).with("/jobs", body: anything)
    end
  end
end
