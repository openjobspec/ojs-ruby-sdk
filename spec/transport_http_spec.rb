# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe OJS::Transport::HTTP do
  let(:transport) { described_class.new(OJS_TEST_BASE_URL) }

  describe "#post" do
    it "sends a POST request with JSON body" do
      stub = stub_request(:post, "#{OJS_TEST_API_BASE}/jobs")
        .with(
          headers: {
            "Content-Type" => OJS_TEST_CONTENT_TYPE,
            "Accept" => OJS_TEST_CONTENT_TYPE,
            "OJS-Version" => OJS::SPEC_VERSION,
          }
        )
        .to_return(status: 201, body: '{"id":"job-1"}', headers: { "Content-Type" => OJS_TEST_CONTENT_TYPE })

      result = transport.post("/jobs", body: { "type" => "test" })

      expect(stub).to have_been_requested
      expect(result["id"]).to eq("job-1")
    end

    it "sends POST without body" do
      stub_request(:post, "#{OJS_TEST_API_BASE}/queues/default/pause")
        .to_return(status: 200, body: "{}", headers: { "Content-Type" => OJS_TEST_CONTENT_TYPE })

      result = transport.post("/queues/default/pause")

      expect(result).to eq({})
    end
  end

  describe "#get" do
    it "sends a GET request" do
      stub_request(:get, "#{OJS_TEST_API_BASE}/jobs/job-1")
        .with(headers: { "Accept" => OJS_TEST_CONTENT_TYPE })
        .to_return(status: 200, body: '{"id":"job-1","type":"test"}', headers: { "Content-Type" => OJS_TEST_CONTENT_TYPE })

      result = transport.get("/jobs/job-1")

      expect(result["id"]).to eq("job-1")
    end

    it "sends GET with query parameters" do
      stub_request(:get, "#{OJS_TEST_API_BASE}/jobs?limit=10&offset=0")
        .to_return(status: 200, body: '{"jobs":[]}', headers: { "Content-Type" => OJS_TEST_CONTENT_TYPE })

      result = transport.get("/jobs", params: { limit: 10, offset: 0 })

      expect(result["jobs"]).to eq([])
    end

    it "skips nil query parameters" do
      stub_request(:get, "#{OJS_TEST_API_BASE}/jobs?limit=10")
        .to_return(status: 200, body: '{"jobs":[]}', headers: { "Content-Type" => OJS_TEST_CONTENT_TYPE })

      result = transport.get("/jobs", params: { limit: 10, offset: nil })

      expect(result["jobs"]).to eq([])
    end
  end

  describe "#delete" do
    it "sends a DELETE request" do
      stub_request(:delete, "#{OJS_TEST_API_BASE}/jobs/job-1")
        .to_return(status: 200, body: '{"status":"cancelled"}', headers: { "Content-Type" => OJS_TEST_CONTENT_TYPE })

      result = transport.delete("/jobs/job-1")

      expect(result["status"]).to eq("cancelled")
    end
  end

  describe "User-Agent header" do
    it "sends the SDK version and Ruby version" do
      stub = stub_request(:get, "#{OJS_TEST_API_BASE}/health")
        .with(headers: { "User-Agent" => "ojs-ruby/#{OJS::VERSION} ruby/#{RUBY_VERSION}" })
        .to_return(status: 200, body: '{"status":"ok"}', headers: { "Content-Type" => OJS_TEST_CONTENT_TYPE })

      transport.get("/health")

      expect(stub).to have_been_requested
    end
  end

  describe "custom headers" do
    it "merges custom headers into requests" do
      custom = described_class.new(OJS_TEST_BASE_URL, headers: { "Authorization" => "Bearer token123" })

      stub = stub_request(:get, "#{OJS_TEST_API_BASE}/health")
        .with(headers: { "Authorization" => "Bearer token123" })
        .to_return(status: 200, body: '{"status":"ok"}', headers: { "Content-Type" => OJS_TEST_CONTENT_TYPE })

      custom.get("/health")

      expect(stub).to have_been_requested
    end
  end

  describe "error handling" do
    it "raises ConnectionError on connection refused" do
      stub_request(:get, "#{OJS_TEST_API_BASE}/health")
        .to_raise(Errno::ECONNREFUSED.new("Connection refused"))

      expect { transport.get("/health") }.to raise_error(OJS::ConnectionError, /Connection refused/)
    end

    it "raises ConnectionError on socket error" do
      stub_request(:get, "#{OJS_TEST_API_BASE}/health")
        .to_raise(SocketError.new("getaddrinfo: Name or service not known"))

      expect { transport.get("/health") }.to raise_error(OJS::ConnectionError)
    end

    it "raises TimeoutError on read timeout" do
      stub_request(:get, "#{OJS_TEST_API_BASE}/health")
        .to_raise(Net::ReadTimeout.new("Net::ReadTimeout"))

      expect { transport.get("/health") }.to raise_error(OJS::TimeoutError, /timed out/)
    end

    it "raises TimeoutError on open timeout" do
      stub_request(:post, "#{OJS_TEST_API_BASE}/jobs")
        .to_raise(Net::OpenTimeout.new("execution expired"))

      expect { transport.post("/jobs", body: {}) }.to raise_error(OJS::TimeoutError)
    end

    it "raises ValidationError on 400" do
      stub_request(:post, "#{OJS_TEST_API_BASE}/jobs")
        .to_return(
          status: 400,
          body: { "error" => { "code" => "invalid_request", "message" => "Missing type" } }.to_json,
          headers: { "Content-Type" => OJS_TEST_CONTENT_TYPE }
        )

      expect { transport.post("/jobs", body: {}) }.to raise_error(OJS::ValidationError, "Missing type")
    end

    it "raises NotFoundError on 404" do
      stub_request(:get, "#{OJS_TEST_API_BASE}/jobs/missing")
        .to_return(
          status: 404,
          body: { "error" => { "code" => "not_found", "message" => "Job not found" } }.to_json,
          headers: { "Content-Type" => OJS_TEST_CONTENT_TYPE }
        )

      expect { transport.get("/jobs/missing") }.to raise_error(OJS::NotFoundError)
    end

    it "raises ConflictError with existing_job_id on 409 duplicate" do
      stub_request(:post, "#{OJS_TEST_API_BASE}/jobs")
        .to_return(
          status: 409,
          body: {
            "error" => {
              "code" => "duplicate",
              "message" => "Duplicate job",
              "details" => { "existing_job_id" => "existing-456" },
            },
          }.to_json,
          headers: { "Content-Type" => OJS_TEST_CONTENT_TYPE }
        )

      expect { transport.post("/jobs", body: {}) }.to raise_error(OJS::ConflictError) { |e|
        expect(e.existing_job_id).to eq("existing-456")
      }
    end

    it "raises PayloadTooLargeError on 413" do
      stub_request(:post, "#{OJS_TEST_API_BASE}/jobs")
        .to_return(
          status: 413,
          body: { "error" => { "message" => "Payload too large" } }.to_json,
          headers: { "Content-Type" => OJS_TEST_CONTENT_TYPE }
        )

      expect { transport.post("/jobs", body: {}) }.to raise_error(OJS::PayloadTooLargeError)
    end

    it "raises UnsupportedError on 422" do
      stub_request(:post, "#{OJS_TEST_API_BASE}/workflows")
        .to_return(
          status: 422,
          body: { "error" => { "message" => "Workflows not supported" } }.to_json,
          headers: { "Content-Type" => OJS_TEST_CONTENT_TYPE }
        )

      expect { transport.post("/workflows", body: {}) }.to raise_error(OJS::UnsupportedError)
    end

    it "raises RateLimitError with retry_after on 429" do
      stub_request(:post, "#{OJS_TEST_API_BASE}/jobs")
        .to_return(
          status: 429,
          body: { "error" => { "code" => "rate_limited", "message" => "Slow down" } }.to_json,
          headers: { "Content-Type" => OJS_TEST_CONTENT_TYPE, "Retry-After" => "60" }
        )

      expect { transport.post("/jobs", body: {}) }.to raise_error(OJS::RateLimitError) { |e|
        expect(e.retry_after).to eq(60)
        expect(e.retryable?).to be true
      }
    end

    it "raises RateLimitError with full rate_limit info on 429" do
      stub_request(:post, "#{OJS_TEST_API_BASE}/jobs")
        .to_return(
          status: 429,
          body: { "error" => { "code" => "rate_limited", "message" => "Slow down" } }.to_json,
          headers: {
            "Content-Type" => OJS_TEST_CONTENT_TYPE,
            "Retry-After" => "30",
            "X-RateLimit-Limit" => "1000",
            "X-RateLimit-Remaining" => "0",
            "X-RateLimit-Reset" => "1700000000",
          }
        )

      expect { transport.post("/jobs", body: {}) }.to raise_error(OJS::RateLimitError) { |e|
        expect(e.retry_after).to eq(30)
        expect(e.rate_limit).not_to be_nil
        expect(e.rate_limit.limit).to eq(1000)
        expect(e.rate_limit.remaining).to eq(0)
        expect(e.rate_limit.reset).to eq(1_700_000_000)
        expect(e.rate_limit.retry_after).to eq(30)
      }
    end

    it "raises ServerError on 500" do
      stub_request(:get, "#{OJS_TEST_API_BASE}/health")
        .to_return(
          status: 500,
          body: { "error" => { "code" => "backend_error", "message" => "Redis down" } }.to_json,
          headers: { "Content-Type" => OJS_TEST_CONTENT_TYPE }
        )

      expect { transport.get("/health") }.to raise_error(OJS::ServerError) { |e|
        expect(e.retryable?).to be true
        expect(e.http_status).to eq(500)
      }
    end

    it "raises ServerError on 503" do
      stub_request(:get, "#{OJS_TEST_API_BASE}/health")
        .to_return(
          status: 503,
          body: { "error" => { "message" => "Service unavailable" } }.to_json,
          headers: { "Content-Type" => OJS_TEST_CONTENT_TYPE }
        )

      expect { transport.get("/health") }.to raise_error(OJS::ServerError) { |e|
        expect(e.http_status).to eq(503)
      }
    end

    it "raises generic Error on unexpected status codes" do
      stub_request(:get, "#{OJS_TEST_API_BASE}/health")
        .to_return(
          status: 418,
          body: "I'm a teapot",
          headers: { "Content-Type" => "text/plain" }
        )

      expect { transport.get("/health") }.to raise_error(OJS::Error, /Unexpected response: 418/)
    end

    it "raises Error on malformed JSON in success response" do
      stub_request(:get, "#{OJS_TEST_API_BASE}/health")
        .to_return(
          status: 200,
          body: "not json{{{",
          headers: { "Content-Type" => OJS_TEST_CONTENT_TYPE }
        )

      expect { transport.get("/health") }.to raise_error(OJS::Error, /Invalid JSON/)
    end

    it "handles malformed JSON in error response gracefully" do
      stub_request(:get, "#{OJS_TEST_API_BASE}/health")
        .to_return(
          status: 500,
          body: "Internal Server Error",
          headers: { "Content-Type" => "text/plain" }
        )

      expect { transport.get("/health") }.to raise_error(OJS::ServerError)
    end

    it "handles empty body on success" do
      stub_request(:post, "#{OJS_TEST_API_BASE}/queues/default/pause")
        .to_return(status: 200, body: "", headers: {})

      result = transport.post("/queues/default/pause")

      expect(result).to be_nil
    end

    it "retries once on stale connection then succeeds" do
      call_count = 0
      stub_request(:get, "#{OJS_TEST_API_BASE}/health")
        .to_return do |_request|
          call_count += 1
          if call_count == 1
            raise Errno::ECONNRESET.new("Connection reset by peer")
          else
            { status: 200, body: '{"status":"ok"}',
              headers: { "Content-Type" => OJS_TEST_CONTENT_TYPE } }
          end
        end

      result = transport.get("/health")

      expect(result["status"]).to eq("ok")
      expect(call_count).to eq(2)
    end

    it "raises ConnectionError after retry also fails" do
      stub_request(:get, "#{OJS_TEST_API_BASE}/health")
        .to_raise(Errno::ECONNRESET.new("Connection reset by peer"))

      expect { transport.get("/health") }.to raise_error(OJS::ConnectionError, /Connection reset/)
    end
  end
end
