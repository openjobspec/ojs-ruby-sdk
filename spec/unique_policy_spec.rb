# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe OJS::UniquePolicy do
  describe ".new" do
    it "uses defaults when no args provided" do
      policy = described_class.new

      expect(policy.keys).to eq(["type"])
      expect(policy.args_keys).to be_nil
      expect(policy.meta_keys).to be_nil
      expect(policy.period).to be_nil
      expect(policy.states).to eq(%w[available active scheduled retryable pending])
      expect(policy.on_conflict).to eq("reject")
    end

    it "accepts custom keys" do
      policy = described_class.new(keys: ["type", "queue", "args"])

      expect(policy.keys).to eq(["type", "queue", "args"])
    end

    it "accepts singular key parameter" do
      policy = described_class.new(key: ["type", "args"])

      expect(policy.keys).to eq(["type", "args"])
    end

    it "accepts symbol keys and converts to strings" do
      policy = described_class.new(keys: [:type, :queue])

      expect(policy.keys).to eq(["type", "queue"])
    end

    it "accepts args_keys and meta_keys" do
      policy = described_class.new(
        keys: ["type", "args", "meta"],
        args_keys: ["user_id"],
        meta_keys: ["tenant_id"]
      )

      expect(policy.args_keys).to eq(["user_id"])
      expect(policy.meta_keys).to eq(["tenant_id"])
    end

    it "accepts period and states" do
      policy = described_class.new(
        period: "PT1H",
        states: %w[available active]
      )

      expect(policy.period).to eq("PT1H")
      expect(policy.states).to eq(%w[available active])
    end

    it "accepts all conflict strategies" do
      %w[reject replace replace_except_schedule ignore].each do |strategy|
        policy = described_class.new(on_conflict: strategy)

        expect(policy.on_conflict).to eq(strategy)
      end
    end
  end

  describe "validation" do
    it "raises on invalid keys" do
      expect {
        described_class.new(keys: ["type", "invalid_key"])
      }.to raise_error(ArgumentError, /Invalid unique keys/)
    end

    it "raises when meta is in keys but meta_keys is missing" do
      expect {
        described_class.new(keys: ["type", "meta"])
      }.to raise_error(ArgumentError, /meta_keys required/)
    end

    it "raises on invalid on_conflict" do
      expect {
        described_class.new(on_conflict: "explode")
      }.to raise_error(ArgumentError, /Invalid on_conflict/)
    end

    it "allows meta key when meta_keys is provided" do
      expect {
        described_class.new(keys: ["type", "meta"], meta_keys: ["tenant_id"])
      }.not_to raise_error
    end
  end

  describe ".from_hash" do
    it "returns nil for nil input" do
      expect(described_class.from_hash(nil)).to be_nil
    end

    it "builds from wire format" do
      hash = {
        "keys" => ["type", "args"],
        "args_keys" => ["user_id"],
        "period" => "PT1H",
        "states" => %w[available active],
        "on_conflict" => "replace",
      }

      policy = described_class.from_hash(hash)

      expect(policy.keys).to eq(["type", "args"])
      expect(policy.args_keys).to eq(["user_id"])
      expect(policy.period).to eq("PT1H")
      expect(policy.states).to eq(%w[available active])
      expect(policy.on_conflict).to eq("replace")
    end

    it "handles symbol keys" do
      hash = { keys: ["type"], on_conflict: "reject" }

      policy = described_class.from_hash(hash)

      expect(policy.keys).to eq(["type"])
    end
  end

  describe "#to_hash" do
    it "serializes required fields" do
      policy = described_class.new(keys: ["type", "args"])
      hash = policy.to_hash

      expect(hash["keys"]).to eq(["type", "args"])
    end

    it "omits default states" do
      policy = described_class.new
      hash = policy.to_hash

      expect(hash).not_to have_key("states")
    end

    it "includes non-default states" do
      policy = described_class.new(states: %w[available active])
      hash = policy.to_hash

      expect(hash["states"]).to eq(%w[available active])
    end

    it "omits default on_conflict" do
      policy = described_class.new
      hash = policy.to_hash

      expect(hash).not_to have_key("on_conflict")
    end

    it "includes non-default on_conflict" do
      policy = described_class.new(on_conflict: "replace")
      hash = policy.to_hash

      expect(hash["on_conflict"]).to eq("replace")
    end

    it "includes optional fields when present" do
      policy = described_class.new(
        keys: ["type", "args"],
        args_keys: ["user_id"],
        period: "PT30M"
      )
      hash = policy.to_hash

      expect(hash["args_keys"]).to eq(["user_id"])
      expect(hash["period"]).to eq("PT30M")
    end

    it "omits nil optional fields" do
      policy = described_class.new
      hash = policy.to_hash

      expect(hash).not_to have_key("args_keys")
      expect(hash).not_to have_key("meta_keys")
      expect(hash).not_to have_key("period")
    end
  end

  describe "#inspect" do
    it "returns a readable representation" do
      policy = described_class.new(keys: ["type", "args"], on_conflict: "replace")

      expect(policy.inspect).to eq('#<OJS::UniquePolicy keys=["type", "args"] on_conflict="replace">')
    end
  end
end
