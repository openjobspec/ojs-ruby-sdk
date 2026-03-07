# frozen_string_literal: true

require "spec_helper"
require "ojs/durable"

RSpec.describe OJS::DurableContext do
  let(:job) { OJS::Job.from_hash(sample_job_response) }
  let(:checkpoint_url) { "#{OJS_TEST_BASE_URL}/ojs/v1/jobs/#{job.id}/checkpoint" }
  # DurableContext expects ctx.server_url and ctx.job
  let(:ctx) { double("ctx", server_url: OJS_TEST_BASE_URL, job: job) }

  before do
    stub_request(:get, checkpoint_url).to_return(status: 404, body: "")
  end

  def context_with_replay_log(log)
    stub_request(:get, checkpoint_url).to_return(
      status: 200,
      body: JSON.generate({ "state" => { "replay_log" => log } }),
      headers: { "Content-Type" => "application/json" }
    )
    OJS::DurableContext.new(ctx)
  end

  describe "#now" do
    it "returns a Time object" do
      dc = OJS::DurableContext.new(ctx)
      expect(dc.now).to be_a(Time)
    end

    it "records a 'now' entry in the replay log" do
      dc = OJS::DurableContext.new(ctx)
      dc.now
      expect(dc.replay_log.size).to eq(1)
      expect(dc.replay_log.first["type"]).to eq("now")
    end

    it "replays the same Time from an existing log" do
      dc1 = OJS::DurableContext.new(ctx)
      t1 = dc1.now

      dc2 = context_with_replay_log(dc1.replay_log)
      expect(dc2.now).to eq(t1)
    end
  end

  describe "#random" do
    it "returns a hex string of 2*num_bytes length" do
      dc = OJS::DurableContext.new(ctx)
      hex = dc.random(16)
      expect(hex).to be_a(String)
      expect(hex.length).to eq(32)
      expect(hex).to match(/\A[0-9a-f]+\z/)
    end

    it "records a 'random' entry in the replay log" do
      dc = OJS::DurableContext.new(ctx)
      dc.random(8)
      expect(dc.replay_log.size).to eq(1)
      expect(dc.replay_log.first["type"]).to eq("random")
    end

    it "replays the same hex from an existing log" do
      dc1 = OJS::DurableContext.new(ctx)
      hex1 = dc1.random(16)

      dc2 = context_with_replay_log(dc1.replay_log)
      expect(dc2.random(16)).to eq(hex1)
    end
  end

  describe "#side_effect" do
    it "executes the block and returns its result" do
      dc = OJS::DurableContext.new(ctx)
      result = dc.side_effect("op") { { "answer" => 42 } }
      expect(result).to eq({ "answer" => 42 })
    end

    it "records a 'side_effect' entry with the given key" do
      dc = OJS::DurableContext.new(ctx)
      dc.side_effect("api-call") { "ok" }
      expect(dc.replay_log.size).to eq(1)
      expect(dc.replay_log.first["type"]).to eq("side_effect")
      expect(dc.replay_log.first["key"]).to eq("api-call")
    end

    it "replays without re-executing the block" do
      dc1 = OJS::DurableContext.new(ctx)
      dc1.side_effect("op") { "original" }

      dc2 = context_with_replay_log(dc1.replay_log)
      replayed = dc2.side_effect("op") { "different" }
      expect(replayed).to eq("original")
    end

    it "raises ArgumentError when no block is given" do
      dc = OJS::DurableContext.new(ctx)
      expect { dc.side_effect("op") }.to raise_error(ArgumentError)
    end
  end

  describe "multi-operation replay" do
    it "replays multiple operations in sequence order" do
      dc1 = OJS::DurableContext.new(ctx)
      t = dc1.now
      r = dc1.random(8)
      s = dc1.side_effect("fetch") { "data" }
      expect(dc1.replay_log.size).to eq(3)

      dc2 = context_with_replay_log(dc1.replay_log)
      expect(dc2.now).to eq(t)
      expect(dc2.random(8)).to eq(r)
      expect(dc2.side_effect("fetch") { "other" }).to eq("data")
    end
  end

  describe "#save" do
    it "sends PUT to the checkpoint endpoint" do
      stub = stub_request(:put, checkpoint_url)
               .to_return(status: 200, body: "")

      dc = OJS::DurableContext.new(ctx)
      dc.save({ "step" => 1 })
      expect(stub).to have_been_requested
    end
  end

  describe "#resume" do
    it "returns nil when no checkpoint exists" do
      dc = OJS::DurableContext.new(ctx)
      expect(dc.resume).to be_nil
    end

    it "returns the saved state when a checkpoint exists" do
      stub_request(:get, checkpoint_url).to_return(
        status: 200,
        body: JSON.generate({ "state" => { "step" => 5 } }),
        headers: { "Content-Type" => "application/json" }
      )
      dc = OJS::DurableContext.new(ctx)
      expect(dc.resume).to eq({ "step" => 5 })
    end
  end

  describe "#complete" do
    it "sends DELETE to the checkpoint endpoint" do
      stub = stub_request(:delete, checkpoint_url)
               .to_return(status: 200, body: "")

      dc = OJS::DurableContext.new(ctx)
      expect(dc.complete).to be_truthy
    end
  end

  describe "#replay_log" do
    it "is empty for a fresh context" do
      dc = OJS::DurableContext.new(ctx)
      expect(dc.replay_log).to eq([])
    end
  end
end
