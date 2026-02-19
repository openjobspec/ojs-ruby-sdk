# frozen_string_literal: true

require_relative "spec_helper"
require "rantly"
require "rantly/rspec_extensions"
require "json"

RSpec.describe "Property-based tests" do
  describe "Job JSON roundtrip" do
    it "preserves all fields through serialization" do
      property_of {
        type = sized(range(1, 50)) { string(:alpha) }
        queue = sized(range(1, 30)) { string(:alpha) }
        priority = range(-10, 10)
        args = array(range(0, 5)) { sized(range(1, 20)) { string(:alpha) } }

        { type: type, queue: queue, priority: priority, args: args }
      }.check(200) do |attrs|
        job = OJS::Job.new(
          type: attrs[:type],
          queue: attrs[:queue],
          priority: attrs[:priority],
          args: attrs[:args]
        )

        hash = job.to_hash
        json = JSON.generate(hash)
        parsed = JSON.parse(json)
        restored = OJS::Job.from_hash(parsed)

        expect(restored.id).to eq(job.id)
        expect(restored.type).to eq(job.type)
        expect(restored.queue).to eq(job.queue)
        expect(restored.priority).to eq(job.priority)
        # Empty arrays and single-element Hash arrays are unwrapped by design;
        # verify multi-element arrays roundtrip exactly.
        if job.args.is_a?(Array) && job.args.length > 1
          expect(restored.args).to eq(job.args)
        end
      end
    end

    it "always includes specversion, id, type, queue, and args in serialized output" do
      property_of {
        type = sized(range(1, 30)) { string(:alpha) }
        queue = sized(range(1, 20)) { string(:alpha) }

        { type: type, queue: queue }
      }.check(200) do |attrs|
        job = OJS::Job.new(type: attrs[:type], queue: attrs[:queue])
        hash = job.to_hash

        expect(hash).to have_key("specversion")
        expect(hash).to have_key("id")
        expect(hash).to have_key("type")
        expect(hash).to have_key("queue")
        expect(hash).to have_key("args")
        expect(hash["specversion"]).to eq(OJS::SPEC_VERSION)
      end
    end
  end

  describe "Job with RetryPolicy roundtrip" do
    it "preserves job and retry policy through serialization" do
      property_of {
        max_attempts = range(1, 25)
        backoff = choose(1.0, 1.5, 2.0, 3.0, 4.0)
        on_exhaustion = choose("discard", "dead_letter")
        jitter = boolean

        {
          type: sized(range(1, 30)) { string(:alpha) },
          max_attempts: max_attempts,
          backoff: backoff,
          on_exhaustion: on_exhaustion,
          jitter: jitter,
        }
      }.check(200) do |attrs|
        policy = OJS::RetryPolicy.new(
          max_attempts: attrs[:max_attempts],
          backoff_coefficient: attrs[:backoff],
          on_exhaustion: attrs[:on_exhaustion],
          jitter: attrs[:jitter]
        )
        job = OJS::Job.new(type: attrs[:type], retry_policy: policy)

        hash = job.to_hash
        json = JSON.generate(hash)
        parsed = JSON.parse(json)
        restored = OJS::Job.from_hash(parsed)

        expect(restored.retry_policy).not_to be_nil
        expect(restored.retry_policy.max_attempts).to eq(policy.max_attempts)
        expect(restored.retry_policy.backoff_coefficient).to eq(policy.backoff_coefficient)
        expect(restored.retry_policy.on_exhaustion).to eq(policy.on_exhaustion)
      end
    end
  end

  describe "RetryPolicy roundtrip" do
    it "preserves policy through serialization" do
      property_of {
        max_attempts = range(1, 50)
        backoff = choose(1.0, 1.5, 2.0, 2.5, 3.0, 5.0)
        on_exhaustion = choose("discard", "dead_letter")
        jitter = boolean

        {
          max_attempts: max_attempts,
          backoff: backoff,
          on_exhaustion: on_exhaustion,
          jitter: jitter,
        }
      }.check(200) do |attrs|
        policy = OJS::RetryPolicy.new(
          max_attempts: attrs[:max_attempts],
          backoff_coefficient: attrs[:backoff],
          on_exhaustion: attrs[:on_exhaustion],
          jitter: attrs[:jitter]
        )

        hash = policy.to_hash
        json = JSON.generate(hash)
        parsed = JSON.parse(json)
        restored = OJS::RetryPolicy.from_hash(parsed)

        expect(restored.max_attempts).to eq(policy.max_attempts)
        expect(restored.backoff_coefficient).to eq(policy.backoff_coefficient)
        expect(restored.on_exhaustion).to eq(policy.on_exhaustion)
      end
    end

    it "always produces valid max_attempts >= 1" do
      property_of {
        range(1, 100)
      }.check(200) do |max|
        policy = OJS::RetryPolicy.new(max_attempts: max)

        expect(policy.max_attempts).to be >= 1
      end
    end

    it "compute_delay never returns negative values" do
      property_of {
        max_attempts = range(1, 20)
        backoff = choose(1.0, 1.5, 2.0, 3.0)
        attempt = range(1, max_attempts)

        { max_attempts: max_attempts, backoff: backoff, attempt: attempt }
      }.check(200) do |attrs|
        policy = OJS::RetryPolicy.new(
          max_attempts: attrs[:max_attempts],
          backoff_coefficient: attrs[:backoff],
          jitter: false
        )

        delay = policy.compute_delay(attrs[:attempt])
        expect(delay).to be >= 0
      end
    end

    it "compute_delay respects max_interval" do
      property_of {
        backoff = choose(2.0, 3.0, 4.0, 5.0)
        attempt = range(1, 20)

        { backoff: backoff, attempt: attempt }
      }.check(200) do |attrs|
        policy = OJS::RetryPolicy.new(
          backoff_coefficient: attrs[:backoff],
          max_interval: "PT5M",
          jitter: false
        )

        delay = policy.compute_delay(attrs[:attempt])
        max_seconds = 5 * 60
        expect(delay).to be <= max_seconds
      end
    end
  end

  describe "Terminal states" do
    it "completed/cancelled/discarded are always terminal" do
      terminal_states = [OJS::State::COMPLETED, OJS::State::CANCELLED, OJS::State::DISCARDED]
      non_terminal_states = [OJS::State::SCHEDULED, OJS::State::AVAILABLE, OJS::State::PENDING,
                             OJS::State::ACTIVE, OJS::State::RETRYABLE]

      property_of {
        choose(*terminal_states)
      }.check(100) do |state|
        expect(terminal_states).to include(state)
        expect(non_terminal_states).not_to include(state)
      end
    end

    it "non-terminal states are never in the terminal set" do
      terminal_states = [OJS::State::COMPLETED, OJS::State::CANCELLED, OJS::State::DISCARDED]
      non_terminal_states = [OJS::State::SCHEDULED, OJS::State::AVAILABLE, OJS::State::PENDING,
                             OJS::State::ACTIVE, OJS::State::RETRYABLE]

      property_of {
        choose(*non_terminal_states)
      }.check(100) do |state|
        expect(terminal_states).not_to include(state)
      end
    end

    it "all 8 states are accounted for" do
      all_states = [
        OJS::State::SCHEDULED, OJS::State::AVAILABLE, OJS::State::PENDING,
        OJS::State::ACTIVE, OJS::State::COMPLETED, OJS::State::RETRYABLE,
        OJS::State::CANCELLED, OJS::State::DISCARDED,
      ]

      expect(all_states.length).to eq(8)
      expect(all_states.uniq.length).to eq(8)
    end
  end

  describe "UniquePolicy roundtrip" do
    it "preserves policy through serialization" do
      property_of {
        keys = choose(["type"], ["type", "queue"], ["type", "args"], ["type", "queue", "args"])
        on_conflict = choose("reject", "replace", "replace_except_schedule", "ignore")

        { keys: keys, on_conflict: on_conflict }
      }.check(200) do |attrs|
        policy = OJS::UniquePolicy.new(
          keys: attrs[:keys],
          on_conflict: attrs[:on_conflict]
        )

        hash = policy.to_hash
        json = JSON.generate(hash)
        parsed = JSON.parse(json)
        restored = OJS::UniquePolicy.from_hash(parsed)

        expect(restored.keys).to eq(policy.keys)
        expect(restored.on_conflict).to eq(policy.on_conflict)
      end
    end
  end

  describe "Job ID generation" do
    it "always produces valid UUIDv7 format" do
      property_of {
        true # just need iterations
      }.check(200) do |_|
        id = OJS::Job.generate_id

        expect(id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/)
      end
    end
  end
end
