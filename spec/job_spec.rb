# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe OJS::Job do
  describe ".new" do
    it "generates a UUIDv7 when no id is provided" do
      job = described_class.new(type: "test.job")

      expect(job.id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/)
    end

    it "uses the provided id" do
      job = described_class.new(type: "test.job", id: "custom-id")

      expect(job.id).to eq("custom-id")
    end

    it "defaults queue to 'default'" do
      job = described_class.new(type: "test.job")

      expect(job.queue).to eq("default")
    end

    it "defaults args to empty hash" do
      job = described_class.new(type: "test.job")

      expect(job.args).to eq({})
    end

    it "defaults meta to empty hash" do
      job = described_class.new(type: "test.job")

      expect(job.meta).to eq({})
    end

    it "accepts all optional attributes" do
      policy = OJS::RetryPolicy.new(max_attempts: 5)
      unique = OJS::UniquePolicy.new(keys: ["type"])

      job = described_class.new(
        type: "test.job",
        args: { "key" => "value" },
        queue: "email",
        meta: { "trace_id" => "abc" },
        priority: 10,
        timeout: 300,
        scheduled_at: "2026-01-01T00:00:00Z",
        expires_at: "2026-12-31T23:59:59Z",
        retry_policy: policy,
        unique_policy: unique,
        schema: "v1",
        state: "active",
        attempt: 2,
        created_at: "2026-01-01T00:00:00Z",
        enqueued_at: "2026-01-01T00:00:01Z",
        started_at: "2026-01-01T00:00:02Z",
        completed_at: "2026-01-01T00:00:03Z",
        error: { "message" => "oops" },
        result: { "status" => "done" }
      )

      expect(job.type).to eq("test.job")
      expect(job.queue).to eq("email")
      expect(job.priority).to eq(10)
      expect(job.timeout).to eq(300)
      expect(job.retry_policy).to eq(policy)
      expect(job.unique_policy).to eq(unique)
      expect(job.state).to eq("active")
      expect(job.attempt).to eq(2)
      expect(job.result).to eq({ "status" => "done" })
    end
  end

  describe ".generate_id" do
    it "generates valid UUIDv7 format" do
      id = described_class.generate_id

      expect(id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/)
    end

    it "generates unique IDs" do
      ids = 100.times.map { described_class.generate_id }

      expect(ids.uniq.size).to eq(100)
    end

    it "generates time-sortable IDs" do
      id1 = described_class.generate_id
      sleep(0.01)
      id2 = described_class.generate_id

      expect(id1 < id2).to be true
    end
  end

  describe "#to_hash" do
    it "serializes required fields" do
      job = described_class.new(type: "email.send", args: { "to" => "user@example.com" })
      hash = job.to_hash

      expect(hash["specversion"]).to eq(OJS::SPEC_VERSION)
      expect(hash["id"]).to be_a(String)
      expect(hash["type"]).to eq("email.send")
      expect(hash["queue"]).to eq("default")
    end

    it "wraps Hash args in an array" do
      job = described_class.new(type: "test.job", args: { "key" => "value" })
      hash = job.to_hash

      expect(hash["args"]).to eq([{ "key" => "value" }])
    end

    it "keeps Array args as-is" do
      job = described_class.new(type: "test.job", args: [1, 2, 3])
      hash = job.to_hash

      expect(hash["args"]).to eq([1, 2, 3])
    end

    it "stringifies Hash arg keys" do
      job = described_class.new(type: "test.job", args: { key: "value" })
      hash = job.to_hash

      expect(hash["args"]).to eq([{ "key" => "value" }])
    end

    it "omits nil optional fields" do
      job = described_class.new(type: "test.job")
      hash = job.to_hash

      expect(hash).not_to have_key("priority")
      expect(hash).not_to have_key("timeout")
      expect(hash).not_to have_key("scheduled_at")
      expect(hash).not_to have_key("expires_at")
      expect(hash).not_to have_key("retry")
      expect(hash).not_to have_key("unique")
      expect(hash).not_to have_key("schema")
    end

    it "omits empty meta" do
      job = described_class.new(type: "test.job", meta: {})
      hash = job.to_hash

      expect(hash).not_to have_key("meta")
    end

    it "includes non-empty meta" do
      job = described_class.new(type: "test.job", meta: { "trace_id" => "abc" })
      hash = job.to_hash

      expect(hash["meta"]).to eq({ "trace_id" => "abc" })
    end

    it "includes retry policy when set" do
      policy = OJS::RetryPolicy.new(max_attempts: 5)
      job = described_class.new(type: "test.job", retry_policy: policy)
      hash = job.to_hash

      expect(hash["retry"]).to eq({ "max_attempts" => 5 })
    end

    it "includes unique policy when set" do
      unique = OJS::UniquePolicy.new(keys: ["type", "args"])
      job = described_class.new(type: "test.job", unique_policy: unique)
      hash = job.to_hash

      expect(hash["unique"]).to include("keys" => ["type", "args"])
    end
  end

  describe ".from_hash" do
    it "deserializes a wire-format hash" do
      hash = {
        "id" => "job-123",
        "type" => "email.send",
        "queue" => "email",
        "args" => [{ "to" => "user@example.com" }],
        "state" => "completed",
        "attempt" => 3,
        "created_at" => "2026-01-01T00:00:00Z",
      }

      job = described_class.from_hash(hash)

      expect(job.id).to eq("job-123")
      expect(job.type).to eq("email.send")
      expect(job.queue).to eq("email")
      expect(job.args).to eq({ "to" => "user@example.com" })
      expect(job.state).to eq("completed")
      expect(job.attempt).to eq(3)
    end

    it "unwraps single-element array to Hash" do
      hash = { "type" => "test.job", "args" => [{ "key" => "value" }] }
      job = described_class.from_hash(hash)

      expect(job.args).to eq({ "key" => "value" })
    end

    it "keeps multi-element array as Array" do
      hash = { "type" => "test.job", "args" => [1, 2, 3] }
      job = described_class.from_hash(hash)

      expect(job.args).to eq([1, 2, 3])
    end

    it "handles nil args" do
      hash = { "type" => "test.job", "args" => nil }
      job = described_class.from_hash(hash)

      expect(job.args).to eq({})
    end

    it "handles empty array args" do
      hash = { "type" => "test.job", "args" => [] }
      job = described_class.from_hash(hash)

      expect(job.args).to eq({})
    end

    it "defaults queue to 'default'" do
      hash = { "type" => "test.job" }
      job = described_class.from_hash(hash)

      expect(job.queue).to eq("default")
    end

    it "deserializes retry policy" do
      hash = {
        "type" => "test.job",
        "retry" => { "max_attempts" => 5, "initial_interval" => "PT2S" },
      }
      job = described_class.from_hash(hash)

      expect(job.retry_policy).to be_a(OJS::RetryPolicy)
      expect(job.retry_policy.max_attempts).to eq(5)
    end

    it "deserializes unique policy" do
      hash = {
        "type" => "test.job",
        "unique" => { "keys" => ["type", "args"], "on_conflict" => "reject" },
      }
      job = described_class.from_hash(hash)

      expect(job.unique_policy).to be_a(OJS::UniquePolicy)
      expect(job.unique_policy.keys).to eq(["type", "args"])
    end

    it "handles symbol keys" do
      hash = { type: "test.job", queue: "custom", args: [{ key: "val" }] }
      job = described_class.from_hash(hash)

      expect(job.type).to eq("test.job")
      expect(job.queue).to eq("custom")
    end
  end

  describe "#inspect" do
    it "returns a readable representation" do
      job = described_class.new(type: "email.send", id: "job-123", state: "active")

      expect(job.inspect).to eq('#<OJS::Job id=job-123 type="email.send" queue="default" state="active">')
    end
  end
end
