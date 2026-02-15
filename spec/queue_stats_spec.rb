# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe OJS::QueueStats do
  describe ".new" do
    it "uses defaults for optional fields" do
      stats = described_class.new(name: "default")

      expect(stats.name).to eq("default")
      expect(stats.depth).to eq(0)
      expect(stats.active).to eq(0)
      expect(stats.scheduled).to eq(0)
      expect(stats.retryable).to eq(0)
      expect(stats.dead_letter).to eq(0)
      expect(stats.paused).to be false
      expect(stats.created_at).to be_nil
      expect(stats.updated_at).to be_nil
    end

    it "accepts all fields" do
      stats = described_class.new(
        name: "email",
        depth: 42,
        active: 5,
        scheduled: 10,
        retryable: 3,
        dead_letter: 1,
        paused: true,
        created_at: "2026-01-01T00:00:00Z",
        updated_at: "2026-01-02T00:00:00Z"
      )

      expect(stats.name).to eq("email")
      expect(stats.depth).to eq(42)
      expect(stats.active).to eq(5)
      expect(stats.scheduled).to eq(10)
      expect(stats.retryable).to eq(3)
      expect(stats.dead_letter).to eq(1)
      expect(stats.paused).to be true
    end
  end

  describe "#paused?" do
    it "returns true when paused" do
      stats = described_class.new(name: "test", paused: true)

      expect(stats.paused?).to be true
    end

    it "returns false when not paused" do
      stats = described_class.new(name: "test", paused: false)

      expect(stats.paused?).to be false
    end
  end

  describe ".from_hash" do
    it "builds from wire format with 'queue' key" do
      hash = {
        "queue" => "email",
        "depth" => 42,
        "active" => 5,
        "scheduled" => 10,
        "retryable" => 3,
        "dead_letter" => 1,
        "paused" => true,
        "created_at" => "2026-01-01T00:00:00Z",
        "updated_at" => "2026-01-02T00:00:00Z",
      }

      stats = described_class.from_hash(hash)

      expect(stats.name).to eq("email")
      expect(stats.depth).to eq(42)
      expect(stats.active).to eq(5)
      expect(stats.paused?).to be true
    end

    it "builds from wire format with 'name' key" do
      hash = { "name" => "reports", "depth" => 10 }

      stats = described_class.from_hash(hash)

      expect(stats.name).to eq("reports")
    end

    it "defaults missing numeric fields to 0" do
      hash = { "queue" => "empty" }

      stats = described_class.from_hash(hash)

      expect(stats.depth).to eq(0)
      expect(stats.active).to eq(0)
      expect(stats.scheduled).to eq(0)
    end

    it "handles symbol keys" do
      hash = { queue: "test", depth: 5, paused: false }

      stats = described_class.from_hash(hash)

      expect(stats.name).to eq("test")
      expect(stats.depth).to eq(5)
    end
  end

  describe "#inspect" do
    it "returns a readable representation" do
      stats = described_class.new(name: "email", depth: 42, active: 5, paused: false)

      expect(stats.inspect).to eq('#<OJS::QueueStats name="email" depth=42 active=5 paused=false>')
    end
  end

  describe "#to_hash" do
    it "serializes required fields" do
      stats = described_class.new(name: "email", depth: 42, active: 5)
      hash = stats.to_hash

      expect(hash["queue"]).to eq("email")
      expect(hash["depth"]).to eq(42)
      expect(hash["active"]).to eq(5)
      expect(hash["paused"]).to be false
    end

    it "includes non-zero optional counters" do
      stats = described_class.new(
        name: "email",
        depth: 42,
        active: 5,
        scheduled: 10,
        retryable: 3,
        dead_letter: 1,
        paused: true
      )
      hash = stats.to_hash

      expect(hash["scheduled"]).to eq(10)
      expect(hash["retryable"]).to eq(3)
      expect(hash["dead_letter"]).to eq(1)
      expect(hash["paused"]).to be true
    end

    it "omits zero optional counters" do
      stats = described_class.new(name: "empty")
      hash = stats.to_hash

      expect(hash).not_to have_key("scheduled")
      expect(hash).not_to have_key("retryable")
      expect(hash).not_to have_key("dead_letter")
    end

    it "includes timestamps when present" do
      stats = described_class.new(
        name: "test",
        created_at: "2026-01-01T00:00:00Z",
        updated_at: "2026-01-02T00:00:00Z"
      )
      hash = stats.to_hash

      expect(hash["created_at"]).to eq("2026-01-01T00:00:00Z")
      expect(hash["updated_at"]).to eq("2026-01-02T00:00:00Z")
    end

    it "omits nil timestamps" do
      stats = described_class.new(name: "test")
      hash = stats.to_hash

      expect(hash).not_to have_key("created_at")
      expect(hash).not_to have_key("updated_at")
    end

    it "round-trips through from_hash" do
      original = described_class.new(
        name: "email",
        depth: 42,
        active: 5,
        scheduled: 10,
        retryable: 3,
        dead_letter: 1,
        paused: true,
        created_at: "2026-01-01T00:00:00Z",
        updated_at: "2026-01-02T00:00:00Z"
      )

      restored = described_class.from_hash(original.to_hash)

      expect(restored.name).to eq(original.name)
      expect(restored.depth).to eq(original.depth)
      expect(restored.active).to eq(original.active)
      expect(restored.scheduled).to eq(original.scheduled)
      expect(restored.paused?).to eq(original.paused?)
    end
  end
end
