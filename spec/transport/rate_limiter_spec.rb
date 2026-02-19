# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe OJS::Transport::RateLimiter do
  describe "#initialize" do
    it "uses default values" do
      limiter = described_class.new

      expect(limiter.max_retries).to eq(3)
      expect(limiter.min_backoff).to eq(0.5)
      expect(limiter.max_backoff).to eq(30.0)
      expect(limiter.enabled).to be true
      expect(limiter.logger).to be_nil
    end

    it "accepts custom values" do
      logger = Logger.new($stdout)
      limiter = described_class.new(
        max_retries: 5,
        min_backoff: 1.0,
        max_backoff: 60.0,
        enabled: false,
        logger: logger,
      )

      expect(limiter.max_retries).to eq(5)
      expect(limiter.min_backoff).to eq(1.0)
      expect(limiter.max_backoff).to eq(60.0)
      expect(limiter.enabled).to be false
      expect(limiter.logger).to eq(logger)
    end
  end

  describe "#should_retry?" do
    it "returns true when enabled and under max retries" do
      limiter = described_class.new(max_retries: 3)

      expect(limiter.should_retry?(0)).to be true
      expect(limiter.should_retry?(1)).to be true
      expect(limiter.should_retry?(2)).to be true
    end

    it "returns false when attempt reaches max retries" do
      limiter = described_class.new(max_retries: 3)

      expect(limiter.should_retry?(3)).to be false
      expect(limiter.should_retry?(4)).to be false
    end

    it "returns false when disabled" do
      limiter = described_class.new(enabled: false)

      expect(limiter.should_retry?(0)).to be false
    end
  end

  describe "#backoff_duration" do
    it "uses retry_after when provided" do
      limiter = described_class.new(max_backoff: 60.0)

      duration = limiter.backoff_duration(0, retry_after: 10)

      expect(duration).to eq(10.0)
    end

    it "clamps retry_after to max_backoff" do
      limiter = described_class.new(max_backoff: 5.0)

      duration = limiter.backoff_duration(0, retry_after: 60)

      expect(duration).to eq(5.0)
    end

    it "ignores zero retry_after and falls back to exponential backoff" do
      limiter = described_class.new(min_backoff: 1.0, max_backoff: 30.0)

      duration = limiter.backoff_duration(0, retry_after: 0)

      expect(duration).to be_between(0.5, 1.0) # min_backoff * 2^0 * rand(0.5..1.0)
    end

    it "applies exponential backoff without retry_after" do
      limiter = described_class.new(min_backoff: 1.0, max_backoff: 30.0)

      d0 = limiter.backoff_duration(0) # base = 1.0 * 2^0 = 1.0
      d1 = limiter.backoff_duration(1) # base = 1.0 * 2^1 = 2.0
      d2 = limiter.backoff_duration(2) # base = 1.0 * 2^2 = 4.0

      expect(d0).to be_between(0.5, 1.0)
      expect(d1).to be_between(1.0, 2.0)
      expect(d2).to be_between(2.0, 4.0)
    end

    it "caps exponential backoff at max_backoff" do
      limiter = described_class.new(min_backoff: 1.0, max_backoff: 5.0)

      duration = limiter.backoff_duration(10) # base would be 1024.0, capped to 5.0

      expect(duration).to be <= 5.0
    end
  end
end

RSpec.describe "HTTP transport with rate limiter" do
  let(:rate_limiter) { OJS::Transport::RateLimiter.new(max_retries: 3, min_backoff: 0.01, max_backoff: 0.05) }
  let(:transport) { OJS::Transport::HTTP.new(OJS_TEST_BASE_URL, rate_limiter: rate_limiter) }

  describe "automatic retry on 429" do
    it "retries and succeeds after a 429" do
      call_count = 0
      stub_request(:post, "#{OJS_TEST_API_BASE}/jobs")
        .to_return do |_request|
          call_count += 1
          if call_count == 1
            { status: 429,
              body: { "error" => { "code" => "rate_limited", "message" => "Slow down" } }.to_json,
              headers: { "Content-Type" => OJS_TEST_CONTENT_TYPE, "Retry-After" => "1" } }
          else
            { status: 201,
              body: '{"id":"job-1"}',
              headers: { "Content-Type" => OJS_TEST_CONTENT_TYPE } }
          end
        end

      allow(transport).to receive(:sleep)
      result = transport.post("/jobs", body: { "type" => "test" })

      expect(result["id"]).to eq("job-1")
      expect(call_count).to eq(2)
      expect(transport).to have_received(:sleep).once
    end

    it "respects Retry-After header value" do
      call_count = 0
      stub_request(:post, "#{OJS_TEST_API_BASE}/jobs")
        .to_return do |_request|
          call_count += 1
          if call_count == 1
            { status: 429,
              body: { "error" => { "code" => "rate_limited", "message" => "Slow down" } }.to_json,
              headers: { "Content-Type" => OJS_TEST_CONTENT_TYPE, "Retry-After" => "15" } }
          else
            { status: 201,
              body: '{"id":"job-1"}',
              headers: { "Content-Type" => OJS_TEST_CONTENT_TYPE } }
          end
        end

      # max_backoff is 0.05 so 15 gets clamped
      allow(transport).to receive(:sleep)
      transport.post("/jobs", body: { "type" => "test" })

      expect(transport).to have_received(:sleep).with(0.05).once
    end

    it "raises RateLimitError after exhausting max retries" do
      stub_request(:post, "#{OJS_TEST_API_BASE}/jobs")
        .to_return(
          status: 429,
          body: { "error" => { "code" => "rate_limited", "message" => "Slow down" } }.to_json,
          headers: { "Content-Type" => OJS_TEST_CONTENT_TYPE, "Retry-After" => "1" },
        )

      allow(transport).to receive(:sleep)

      expect { transport.post("/jobs", body: { "type" => "test" }) }
        .to raise_error(OJS::RateLimitError)

      # 3 retries = 3 sleeps
      expect(transport).to have_received(:sleep).exactly(3).times
    end

    it "does not retry non-429 errors" do
      stub_request(:post, "#{OJS_TEST_API_BASE}/jobs")
        .to_return(
          status: 500,
          body: { "error" => { "code" => "backend_error", "message" => "Down" } }.to_json,
          headers: { "Content-Type" => OJS_TEST_CONTENT_TYPE },
        )

      allow(transport).to receive(:sleep)

      expect { transport.post("/jobs", body: { "type" => "test" }) }
        .to raise_error(OJS::ServerError)

      expect(transport).not_to have_received(:sleep)
    end

    it "does not retry when rate limiter is disabled" do
      disabled_limiter = OJS::Transport::RateLimiter.new(enabled: false)
      disabled_transport = OJS::Transport::HTTP.new(OJS_TEST_BASE_URL, rate_limiter: disabled_limiter)

      stub_request(:post, "#{OJS_TEST_API_BASE}/jobs")
        .to_return(
          status: 429,
          body: { "error" => { "code" => "rate_limited", "message" => "Slow down" } }.to_json,
          headers: { "Content-Type" => OJS_TEST_CONTENT_TYPE, "Retry-After" => "1" },
        )

      allow(disabled_transport).to receive(:sleep)

      expect { disabled_transport.post("/jobs", body: { "type" => "test" }) }
        .to raise_error(OJS::RateLimitError)

      expect(disabled_transport).not_to have_received(:sleep)
    end

    it "does not retry when no rate limiter is configured" do
      plain_transport = OJS::Transport::HTTP.new(OJS_TEST_BASE_URL)

      stub_request(:post, "#{OJS_TEST_API_BASE}/jobs")
        .to_return(
          status: 429,
          body: { "error" => { "code" => "rate_limited", "message" => "Slow down" } }.to_json,
          headers: { "Content-Type" => OJS_TEST_CONTENT_TYPE, "Retry-After" => "1" },
        )

      expect { plain_transport.post("/jobs", body: { "type" => "test" }) }
        .to raise_error(OJS::RateLimitError)
    end

    it "retries multiple times before succeeding" do
      call_count = 0
      stub_request(:post, "#{OJS_TEST_API_BASE}/jobs")
        .to_return do |_request|
          call_count += 1
          if call_count <= 2
            { status: 429,
              body: { "error" => { "code" => "rate_limited", "message" => "Slow down" } }.to_json,
              headers: { "Content-Type" => OJS_TEST_CONTENT_TYPE } }
          else
            { status: 201,
              body: '{"id":"job-1"}',
              headers: { "Content-Type" => OJS_TEST_CONTENT_TYPE } }
          end
        end

      allow(transport).to receive(:sleep)
      result = transport.post("/jobs", body: { "type" => "test" })

      expect(result["id"]).to eq("job-1")
      expect(call_count).to eq(3)
      expect(transport).to have_received(:sleep).twice
    end

    it "logs retry attempts when logger is provided" do
      logger = instance_double(Logger)
      allow(logger).to receive(:info)

      logging_limiter = OJS::Transport::RateLimiter.new(
        max_retries: 2, min_backoff: 0.01, max_backoff: 0.05, logger: logger,
      )
      logging_transport = OJS::Transport::HTTP.new(OJS_TEST_BASE_URL, rate_limiter: logging_limiter)

      call_count = 0
      stub_request(:post, "#{OJS_TEST_API_BASE}/jobs")
        .to_return do |_request|
          call_count += 1
          if call_count == 1
            { status: 429,
              body: { "error" => { "code" => "rate_limited", "message" => "Slow down" } }.to_json,
              headers: { "Content-Type" => OJS_TEST_CONTENT_TYPE, "Retry-After" => "1" } }
          else
            { status: 201,
              body: '{"id":"job-1"}',
              headers: { "Content-Type" => OJS_TEST_CONTENT_TYPE } }
          end
        end

      allow(logging_transport).to receive(:sleep)
      logging_transport.post("/jobs", body: { "type" => "test" })

      expect(logger).to have_received(:info).with(/retry 1\/2/).once
    end
  end
end

RSpec.describe "Client with retry_config" do
  include OJSTestHelpers

  it "accepts a Hash retry_config" do
    client = OJS::Client.new(base_url, retry_config: { max_retries: 5 })

    stub_ojs_post("/jobs", status: 201, response_body: sample_job_response)

    job = client.enqueue("email.send", to: "user@example.com")
    expect(job).to be_a(OJS::Job)
  end

  it "accepts a RateLimiter retry_config" do
    limiter = OJS::Transport::RateLimiter.new(max_retries: 2)
    client = OJS::Client.new(base_url, retry_config: limiter)

    stub_ojs_post("/jobs", status: 201, response_body: sample_job_response)

    job = client.enqueue("email.send", to: "user@example.com")
    expect(job).to be_a(OJS::Job)
  end

  it "raises ArgumentError for invalid retry_config" do
    expect { OJS::Client.new(base_url, retry_config: "bad") }
      .to raise_error(ArgumentError, /retry_config/)
  end
end
