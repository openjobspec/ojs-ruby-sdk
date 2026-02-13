# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe OJS::Events do
  it "defines core job event constants" do
    expect(OJS::Events::JOB_ENQUEUED).to eq("job.enqueued")
    expect(OJS::Events::JOB_STARTED).to eq("job.started")
    expect(OJS::Events::JOB_COMPLETED).to eq("job.completed")
    expect(OJS::Events::JOB_FAILED).to eq("job.failed")
    expect(OJS::Events::JOB_DISCARDED).to eq("job.discarded")
  end

  it "defines extended job event constants" do
    expect(OJS::Events::JOB_RETRYING).to eq("job.retrying")
    expect(OJS::Events::JOB_CANCELLED).to eq("job.cancelled")
    expect(OJS::Events::JOB_HEARTBEAT).to eq("job.heartbeat")
    expect(OJS::Events::JOB_SCHEDULED).to eq("job.scheduled")
    expect(OJS::Events::JOB_EXPIRED).to eq("job.expired")
    expect(OJS::Events::JOB_PROGRESS).to eq("job.progress")
  end

  it "defines queue event constants" do
    expect(OJS::Events::QUEUE_PAUSED).to eq("queue.paused")
    expect(OJS::Events::QUEUE_RESUMED).to eq("queue.resumed")
  end

  it "defines worker event constants" do
    expect(OJS::Events::WORKER_STARTED).to eq("worker.started")
    expect(OJS::Events::WORKER_STOPPED).to eq("worker.stopped")
    expect(OJS::Events::WORKER_QUIET).to eq("worker.quiet")
    expect(OJS::Events::WORKER_HEARTBEAT).to eq("worker.heartbeat")
  end

  it "defines workflow event constants" do
    expect(OJS::Events::WORKFLOW_STARTED).to eq("workflow.started")
    expect(OJS::Events::WORKFLOW_STEP_COMPLETED).to eq("workflow.step_completed")
    expect(OJS::Events::WORKFLOW_COMPLETED).to eq("workflow.completed")
    expect(OJS::Events::WORKFLOW_FAILED).to eq("workflow.failed")
  end

  it "defines cron event constants" do
    expect(OJS::Events::CRON_TRIGGERED).to eq("cron.triggered")
    expect(OJS::Events::CRON_SKIPPED).to eq("cron.skipped")
  end
end

RSpec.describe OJS::Event do
  describe ".new" do
    it "creates an event with required fields" do
      event = described_class.new(type: "job.completed", data: { "job_id" => "123" })

      expect(event.type).to eq("job.completed")
      expect(event.data).to eq({ "job_id" => "123" })
      expect(event.time).not_to be_nil
    end

    it "generates a default time" do
      event = described_class.new(type: "job.completed", data: {})

      expect(event.time).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    end

    it "accepts all optional fields" do
      event = described_class.new(
        type: "job.completed",
        data: { "status" => "ok" },
        id: "evt-123",
        source: "/ojs/worker/1",
        time: "2026-01-01T00:00:00.000Z",
        subject: "job-456"
      )

      expect(event.id).to eq("evt-123")
      expect(event.source).to eq("/ojs/worker/1")
      expect(event.time).to eq("2026-01-01T00:00:00.000Z")
      expect(event.subject).to eq("job-456")
    end
  end

  describe ".from_hash" do
    it "builds from a parsed JSON hash" do
      hash = {
        "id" => "evt-123",
        "type" => "job.completed",
        "source" => "/ojs/worker/1",
        "time" => "2026-01-01T00:00:00.000Z",
        "subject" => "job-456",
        "data" => { "status" => "ok" },
      }

      event = described_class.from_hash(hash)

      expect(event.id).to eq("evt-123")
      expect(event.type).to eq("job.completed")
      expect(event.source).to eq("/ojs/worker/1")
      expect(event.time).to eq("2026-01-01T00:00:00.000Z")
      expect(event.subject).to eq("job-456")
      expect(event.data).to eq({ "status" => "ok" })
    end

    it "handles symbol keys" do
      hash = { type: "job.started", data: { job_id: "123" } }

      event = described_class.from_hash(hash)

      expect(event.type).to eq("job.started")
    end
  end
end
