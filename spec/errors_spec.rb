# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe OJS::Error do
  describe ".new" do
    it "stores error attributes" do
      error = described_class.new("Something failed",
        code: "custom_error",
        retryable: true,
        details: { "key" => "value" },
        request_id: "req-123",
        http_status: 500
      )

      expect(error.message).to eq("Something failed")
      expect(error.code).to eq("custom_error")
      expect(error.retryable?).to be true
      expect(error.details).to eq({ "key" => "value" })
      expect(error.request_id).to eq("req-123")
      expect(error.http_status).to eq(500)
    end

    it "defaults retryable to false" do
      error = described_class.new("test")

      expect(error.retryable?).to be false
    end
  end

  describe ".from_response" do
    it "maps error codes to specific exception classes" do
      {
        "invalid_request" => OJS::ValidationError,
        "invalid_payload" => OJS::ValidationError,
        "schema_validation" => OJS::ValidationError,
        "not_found" => OJS::NotFoundError,
        "duplicate" => OJS::ConflictError,
        "queue_paused" => OJS::QueuePausedError,
        "rate_limited" => OJS::RateLimitError,
        "backend_error" => OJS::ServerError,
        "timeout" => OJS::TimeoutError,
        "unsupported" => OJS::UnsupportedError,
        "envelope_too_large" => OJS::PayloadTooLargeError,
      }.each do |code, klass|
        body = { "error" => { "code" => code, "message" => "Test" } }
        error = described_class.from_response(body, http_status: 400)

        expect(error).to be_a(klass), "Expected #{klass} for code '#{code}', got #{error.class}"
      end
    end

    it "falls back to base Error for unknown codes" do
      body = { "error" => { "code" => "unknown_code", "message" => "Something" } }
      error = described_class.from_response(body, http_status: 400)

      expect(error).to be_a(OJS::Error)
      expect(error).not_to be_a(OJS::ValidationError)
    end

    it "extracts message from response" do
      body = { "error" => { "code" => "invalid_request", "message" => "Type is required" } }
      error = described_class.from_response(body, http_status: 400)

      expect(error.message).to eq("Type is required")
    end

    it "uses 'Unknown error' when no message present" do
      body = { "error" => { "code" => "invalid_request" } }
      error = described_class.from_response(body, http_status: 400)

      expect(error.message).to eq("Unknown error")
    end

    it "extracts details and request_id" do
      body = {
        "error" => {
          "code" => "invalid_request",
          "message" => "Bad",
          "details" => { "field" => "type" },
          "request_id" => "req-abc",
        },
      }
      error = described_class.from_response(body, http_status: 400)

      expect(error.details).to eq({ "field" => "type" })
      expect(error.request_id).to eq("req-abc")
    end

    it "handles non-hash body gracefully" do
      error = described_class.from_response("not a hash", http_status: 400)

      expect(error).to be_a(OJS::Error)
      expect(error.message).to eq("Unknown error")
    end

    it "handles body without error key" do
      body = { "message" => "Direct message", "code" => "invalid_request" }
      error = described_class.from_response(body, http_status: 400)

      expect(error).to be_a(OJS::ValidationError)
    end

    it "preserves retryable from response" do
      body = { "error" => { "code" => "backend_error", "message" => "Retry", "retryable" => true } }
      error = described_class.from_response(body, http_status: 500)

      expect(error.retryable?).to be true
    end
  end
end

RSpec.describe OJS::ConnectionError do
  it "is retryable by default" do
    error = described_class.new

    expect(error.retryable?).to be true
    expect(error.message).to eq("Connection failed")
  end

  it "accepts a custom message" do
    error = described_class.new("Cannot reach server")

    expect(error.message).to eq("Cannot reach server")
  end
end

RSpec.describe OJS::TimeoutError do
  it "is retryable by default" do
    error = described_class.new

    expect(error.retryable?).to be true
    expect(error.code).to eq("timeout")
  end
end

RSpec.describe OJS::ValidationError do
  it "is not retryable" do
    error = described_class.new

    expect(error.retryable?).to be false
    expect(error.code).to eq("invalid_request")
  end

  it "accepts a custom code" do
    error = described_class.new("Schema error", code: "schema_validation")

    expect(error.code).to eq("schema_validation")
  end
end

RSpec.describe OJS::NotFoundError do
  it "has code 'not_found' and is not retryable" do
    error = described_class.new

    expect(error.code).to eq("not_found")
    expect(error.retryable?).to be false
  end
end

RSpec.describe OJS::ConflictError do
  it "stores existing_job_id" do
    error = described_class.new("Duplicate", existing_job_id: "job-existing")

    expect(error.existing_job_id).to eq("job-existing")
    expect(error.code).to eq("duplicate")
    expect(error.retryable?).to be false
  end

  it "defaults existing_job_id to nil" do
    error = described_class.new

    expect(error.existing_job_id).to be_nil
  end
end

RSpec.describe OJS::QueuePausedError do
  it "is retryable" do
    error = described_class.new

    expect(error.retryable?).to be true
    expect(error.code).to eq("queue_paused")
  end
end

RSpec.describe OJS::RateLimitError do
  it "stores retry_after and is retryable" do
    error = described_class.new("Slow down", retry_after: 30)

    expect(error.retry_after).to eq(30)
    expect(error.retryable?).to be true
    expect(error.code).to eq("rate_limited")
  end

  it "defaults retry_after to nil" do
    error = described_class.new

    expect(error.retry_after).to be_nil
  end
end

RSpec.describe OJS::ServerError do
  it "is retryable" do
    error = described_class.new

    expect(error.retryable?).to be true
    expect(error.code).to eq("backend_error")
  end
end

RSpec.describe OJS::PayloadTooLargeError do
  it "is not retryable" do
    error = described_class.new

    expect(error.retryable?).to be false
    expect(error.code).to eq("envelope_too_large")
  end
end

RSpec.describe OJS::UnsupportedError do
  it "is not retryable" do
    error = described_class.new

    expect(error.retryable?).to be false
    expect(error.code).to eq("unsupported")
  end
end
