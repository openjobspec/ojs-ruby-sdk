# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe OJS::RetryPolicy do
  describe ".new" do
    it "uses defaults when no args provided" do
      policy = described_class.new

      expect(policy.max_attempts).to eq(3)
      expect(policy.initial_interval).to eq("PT1S")
      expect(policy.backoff_coefficient).to eq(2.0)
      expect(policy.max_interval).to eq("PT5M")
      expect(policy.jitter).to be true
      expect(policy.non_retryable_errors).to eq([])
      expect(policy.on_exhaustion).to eq("discard")
    end

    it "accepts custom values" do
      policy = described_class.new(
        max_attempts: 5,
        initial_interval: "PT2S",
        backoff_coefficient: 3.0,
        max_interval: "PT10M",
        jitter: false,
        non_retryable_errors: ["auth.*"],
        on_exhaustion: "dead_letter"
      )

      expect(policy.max_attempts).to eq(5)
      expect(policy.initial_interval).to eq("PT2S")
      expect(policy.backoff_coefficient).to eq(3.0)
      expect(policy.max_interval).to eq("PT10M")
      expect(policy.jitter).to be false
      expect(policy.non_retryable_errors).to eq(["auth.*"])
      expect(policy.on_exhaustion).to eq("dead_letter")
    end

    it "raises on invalid max_attempts" do
      expect { described_class.new(max_attempts: 0) }.to raise_error(ArgumentError, /max_attempts/)
    end

    it "raises on invalid backoff_coefficient" do
      expect { described_class.new(backoff_coefficient: 0.5) }.to raise_error(ArgumentError, /backoff_coefficient/)
    end

    it "raises on invalid on_exhaustion" do
      expect { described_class.new(on_exhaustion: "explode") }.to raise_error(ArgumentError, /on_exhaustion/)
    end
  end

  describe ".from_hash" do
    it "builds from wire format" do
      policy = described_class.from_hash({
        "max_attempts" => 5,
        "initial_interval" => "PT10S",
        "backoff_coefficient" => 4.0,
        "jitter" => false,
      })

      expect(policy.max_attempts).to eq(5)
      expect(policy.initial_interval).to eq("PT10S")
      expect(policy.backoff_coefficient).to eq(4.0)
      expect(policy.jitter).to be false
    end

    it "returns nil for nil input" do
      expect(described_class.from_hash(nil)).to be_nil
    end
  end

  describe "#to_hash" do
    it "serializes non-default values" do
      policy = described_class.new(max_attempts: 5, on_exhaustion: "dead_letter")
      hash = policy.to_hash

      expect(hash["max_attempts"]).to eq(5)
      expect(hash["on_exhaustion"]).to eq("dead_letter")
      # Defaults should be omitted
      expect(hash).not_to have_key("initial_interval")
      expect(hash).not_to have_key("backoff_coefficient")
    end

    it "includes non_retryable_errors when present" do
      policy = described_class.new(non_retryable_errors: ["auth.*", "validation.payload_invalid"])
      hash = policy.to_hash

      expect(hash["non_retryable_errors"]).to eq(["auth.*", "validation.payload_invalid"])
    end
  end

  describe "#compute_delay" do
    it "computes exponential backoff without jitter" do
      policy = described_class.new(
        initial_interval: "PT1S",
        backoff_coefficient: 2.0,
        max_interval: "PT5M",
        jitter: false
      )

      expect(policy.compute_delay(1)).to eq(1.0)   # 1 * 2^0
      expect(policy.compute_delay(2)).to eq(2.0)   # 1 * 2^1
      expect(policy.compute_delay(3)).to eq(4.0)   # 1 * 2^2
      expect(policy.compute_delay(4)).to eq(8.0)   # 1 * 2^3
      expect(policy.compute_delay(5)).to eq(16.0)  # 1 * 2^4
    end

    it "caps at max_interval" do
      policy = described_class.new(
        initial_interval: "PT1S",
        backoff_coefficient: 2.0,
        max_interval: "PT10S",
        jitter: false
      )

      expect(policy.compute_delay(10)).to eq(10.0) # capped
    end

    it "applies jitter within 0.5x-1.5x range" do
      policy = described_class.new(
        initial_interval: "PT10S",
        backoff_coefficient: 1.0,
        jitter: true
      )

      delays = 100.times.map { policy.compute_delay(1) }

      expect(delays.min).to be >= 5.0
      expect(delays.max).to be <= 15.0
      # Not all the same (jitter adds randomness)
      expect(delays.uniq.size).to be > 1
    end
  end

  describe "#non_retryable?" do
    let(:policy) do
      described_class.new(non_retryable_errors: [
        "validation.payload_invalid",
        "auth.*",
      ])
    end

    it "matches exact error types" do
      expect(policy.non_retryable?("validation.payload_invalid")).to be true
    end

    it "matches wildcard prefixes" do
      expect(policy.non_retryable?("auth.token_expired")).to be true
      expect(policy.non_retryable?("auth.forbidden")).to be true
    end

    it "does not match unrelated errors" do
      expect(policy.non_retryable?("validation.schema_error")).to be false
      expect(policy.non_retryable?("external.auth.failure")).to be false
    end
  end

  describe ".parse_duration" do
    it "parses seconds" do
      expect(described_class.parse_duration("PT1S")).to eq(1.0)
      expect(described_class.parse_duration("PT30S")).to eq(30.0)
    end

    it "parses minutes" do
      expect(described_class.parse_duration("PT1M")).to eq(60.0)
      expect(described_class.parse_duration("PT5M")).to eq(300.0)
    end

    it "parses hours" do
      expect(described_class.parse_duration("PT1H")).to eq(3600.0)
    end

    it "parses combined durations" do
      expect(described_class.parse_duration("PT1H30M")).to eq(5400.0)
      expect(described_class.parse_duration("PT1H30M15S")).to eq(5415.0)
    end

    it "parses days" do
      expect(described_class.parse_duration("P1D")).to eq(86_400.0)
      expect(described_class.parse_duration("P7D")).to eq(604_800.0)
    end

    it "raises on invalid input" do
      expect { described_class.parse_duration("invalid") }.to raise_error(ArgumentError)
    end
  end

  describe "equality" do
    it "considers policies with the same attributes as equal" do
      p1 = described_class.new(max_attempts: 5, on_exhaustion: "dead_letter")
      p2 = described_class.new(max_attempts: 5, on_exhaustion: "dead_letter")

      expect(p1).to eq(p2)
      expect(p1.eql?(p2)).to be true
    end

    it "considers policies with different attributes as not equal" do
      p1 = described_class.new(max_attempts: 3)
      p2 = described_class.new(max_attempts: 5)

      expect(p1).not_to eq(p2)
    end

    it "is not equal to non-RetryPolicy objects" do
      policy = described_class.new

      expect(policy).not_to eq("not a policy")
      expect(policy).not_to eq(nil)
    end

    it "produces consistent hash values for equal policies" do
      p1 = described_class.new(max_attempts: 5, jitter: false)
      p2 = described_class.new(max_attempts: 5, jitter: false)

      expect(p1.hash).to eq(p2.hash)
    end

    it "can be used as hash keys" do
      p1 = described_class.new(max_attempts: 5)
      p2 = described_class.new(max_attempts: 5)

      h = { p1 => "found" }
      expect(h[p2]).to eq("found")
    end
  end
end
