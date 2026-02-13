# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe "Workflows" do
  describe OJS::Step do
    it "serializes to wire format" do
      step = OJS::Step.new(type: "email.send", args: { to: "user@example.com" })
      hash = step.to_hash

      expect(hash["type"]).to eq("email.send")
      expect(hash["args"]).to eq([{ "to" => "user@example.com" }])
    end

    it "includes optional fields when set" do
      step = OJS::Step.new(
        type: "report.generate",
        args: { id: 42 },
        queue: "reports",
        priority: 10,
        timeout: 300,
        meta: { trace_id: "abc" }
      )
      hash = step.to_hash

      expect(hash["queue"]).to eq("reports")
      expect(hash["priority"]).to eq(10)
      expect(hash["timeout"]).to eq(300)
      expect(hash["meta"]).to eq({ "trace_id" => "abc" })
    end

    it "includes retry policy when set" do
      policy = OJS::RetryPolicy.new(max_attempts: 5)
      step = OJS::Step.new(type: "test.job", args: {}, retry_policy: policy)
      hash = step.to_hash

      expect(hash["retry"]["max_attempts"]).to eq(5)
    end
  end

  describe "OJS.chain" do
    it "builds a chain workflow definition" do
      definition = OJS.chain(
        OJS::Step.new(type: "step.one", args: { a: 1 }),
        OJS::Step.new(type: "step.two", args: { b: 2 }),
        name: "test-chain"
      )

      expect(definition).to be_a(OJS::WorkflowDefinition)
      expect(definition.workflow_type).to eq("chain")
      expect(definition.name).to eq("test-chain")
      expect(definition.steps.length).to eq(2)
    end

    it "serializes to wire format" do
      definition = OJS.chain(
        OJS::Step.new(type: "step.one", args: { a: 1 }),
        OJS::Step.new(type: "step.two", args: { b: 2 }),
        name: "my-chain"
      )
      hash = definition.to_hash

      expect(hash["type"]).to eq("chain")
      expect(hash["name"]).to eq("my-chain")
      expect(hash["steps"].length).to eq(2)
      expect(hash["steps"][0]["type"]).to eq("step.one")
      expect(hash["steps"][1]["type"]).to eq("step.two")
    end
  end

  describe "OJS.group" do
    it "builds a group workflow definition" do
      definition = OJS.group(
        OJS::Step.new(type: "export.csv", args: { id: 1 }),
        OJS::Step.new(type: "export.pdf", args: { id: 1 }),
        name: "parallel-export"
      )

      expect(definition.workflow_type).to eq("group")
      expect(definition.name).to eq("parallel-export")
      expect(definition.steps.length).to eq(2)
    end

    it "serializes to wire format with jobs key" do
      definition = OJS.group(
        OJS::Step.new(type: "export.csv", args: {}),
        OJS::Step.new(type: "export.pdf", args: {})
      )
      hash = definition.to_hash

      expect(hash["type"]).to eq("group")
      expect(hash).to have_key("jobs")
      expect(hash["jobs"].length).to eq(2)
    end
  end

  describe "OJS.batch" do
    it "builds a batch workflow with callbacks" do
      definition = OJS.batch(
        [
          OJS::Step.new(type: "email.send", args: { to: "a@b.com" }),
          OJS::Step.new(type: "email.send", args: { to: "c@d.com" }),
        ],
        name: "bulk-send",
        on_complete: OJS::Step.new(type: "batch.report", args: {}),
        on_success: OJS::Step.new(type: "batch.celebrate", args: {}),
        on_failure: OJS::Step.new(type: "batch.alert", args: {})
      )

      expect(definition.workflow_type).to eq("batch")
      expect(definition.name).to eq("bulk-send")
      expect(definition.steps.length).to eq(2)
      expect(definition.callbacks[:on_complete]).to be_a(OJS::Step)
      expect(definition.callbacks[:on_success]).to be_a(OJS::Step)
      expect(definition.callbacks[:on_failure]).to be_a(OJS::Step)
    end

    it "serializes callbacks in wire format" do
      definition = OJS.batch(
        [OJS::Step.new(type: "email.send", args: { to: "a@b.com" })],
        on_complete: OJS::Step.new(type: "batch.done", args: { notify: true })
      )
      hash = definition.to_hash

      expect(hash["type"]).to eq("batch")
      expect(hash["jobs"].length).to eq(1)
      expect(hash["callbacks"]["on_complete"]["type"]).to eq("batch.done")
      expect(hash["callbacks"]["on_complete"]["args"]).to eq([{ "notify" => true }])
    end

    it "omits callbacks when none provided" do
      definition = OJS.batch(
        [OJS::Step.new(type: "email.send", args: {})]
      )
      hash = definition.to_hash

      expect(hash).not_to have_key("callbacks")
    end
  end
end
