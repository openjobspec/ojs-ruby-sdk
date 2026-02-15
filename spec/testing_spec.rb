# frozen_string_literal: true

require_relative "spec_helper"
require_relative "../lib/ojs/testing"

RSpec.describe OJS::Testing do
  include described_class

  before { ojs_fake! }
  after  { ojs_restore! }

  describe "fake mode lifecycle" do
    it "activates and deactivates fake mode" do
      expect(OJS::Testing.active_store).to be_a(OJS::Testing::FakeStore)

      ojs_restore!

      expect(OJS::Testing.active_store).to be_nil
    end

    it "raises when accessing store outside fake mode" do
      ojs_restore!

      expect { ojs_store }.to raise_error(RuntimeError, /not in fake mode/)
    end
  end

  describe OJS::Testing::FakeTransport do
    let(:client) { OJS::Client.new("http://fake", transport: OJS::Testing.fake_transport) }

    describe "enqueue" do
      it "records enqueued jobs" do
        job = client.enqueue("email.send", to: "user@example.com")

        expect(job).to be_a(OJS::Job)
        expect(job.type).to eq("email.send")
        expect(job.id).to start_with("fake-")
      end

      it "stores jobs accessible via assertions" do
        client.enqueue("email.send", to: "user@example.com")

        assert_enqueued "email.send"
      end

      it "enqueues to specified queue" do
        client.enqueue("report.generate", { id: 42 }, queue: "reports")

        jobs = all_enqueued(queue: "reports")
        expect(jobs.length).to eq(1)
        expect(jobs[0].type).to eq("report.generate")
      end
    end

    describe "enqueue_batch" do
      it "records multiple jobs" do
        jobs = client.enqueue_batch([
          { type: "email.send", args: { to: "a@b.com" } },
          { type: "email.send", args: { to: "c@d.com" } },
        ])

        expect(jobs.length).to eq(2)
        assert_enqueued "email.send", count: 2
      end
    end

    describe "get_job" do
      it "retrieves an enqueued job by id" do
        enqueued = client.enqueue("email.send", to: "test@example.com")

        fetched = client.get_job(enqueued.id)

        expect(fetched).to be_a(OJS::Job)
        expect(fetched.id).to eq(enqueued.id)
        expect(fetched.type).to eq("email.send")
      end

      it "raises NotFoundError for unknown job" do
        expect { client.get_job("nonexistent") }.to raise_error(OJS::NotFoundError)
      end
    end

    describe "cancel_job" do
      it "marks job as cancelled" do
        job = client.enqueue("email.send", to: "test@example.com")

        result = client.cancel_job(job.id)

        expect(result["status"]).to eq("cancelled")
      end
    end

    describe "workflow" do
      it "returns a workflow response" do
        result = client.workflow(OJS.chain(
          OJS::Step.new(type: "step.one", args: { a: 1 }),
          OJS::Step.new(type: "step.two", args: { b: 2 }),
          name: "test-chain"
        ))

        expect(result["id"]).to start_with("fake-wf-")
        expect(result["type"]).to eq("chain")
        expect(result["state"]).to eq("running")
      end
    end

    describe "queue operations" do
      it "lists queues from enqueued jobs" do
        client.enqueue("email.send", to: "a@b.com")
        client.enqueue("report.gen", { id: 1 }, queue: "reports")

        queues = client.queues

        expect(queues).to include("default", "reports")
      end

      it "returns queue stats" do
        client.enqueue("email.send", to: "a@b.com")

        stats = client.queue_stats("default")

        expect(stats).to be_a(OJS::QueueStats)
        expect(stats.name).to eq("default")
        expect(stats.depth).to be >= 1
      end

      it "pause and resume are no-ops" do
        expect { client.pause_queue("default") }.not_to raise_error
        expect { client.resume_queue("default") }.not_to raise_error
      end
    end

    describe "health" do
      it "returns ok status" do
        health = client.health

        expect(health["status"]).to eq("ok")
      end
    end

    describe "close" do
      it "is a no-op" do
        expect { client.close }.not_to raise_error
      end
    end
  end

  describe "assertions" do
    let(:client) { OJS::Client.new("http://fake", transport: OJS::Testing.fake_transport) }

    it "assert_enqueued passes when job exists" do
      client.enqueue("email.send", to: "user@example.com")

      expect { assert_enqueued("email.send") }.not_to raise_error
    end

    it "assert_enqueued fails when job does not exist" do
      expect { assert_enqueued("email.send") }.to raise_error(RuntimeError, /Expected at least one enqueued job/)
    end

    it "assert_enqueued with count" do
      client.enqueue("email.send", to: "a@b.com")
      client.enqueue("email.send", to: "c@d.com")

      expect { assert_enqueued("email.send", count: 2) }.not_to raise_error
      expect { assert_enqueued("email.send", count: 1) }.to raise_error(RuntimeError, /Expected 1/)
    end

    it "refute_enqueued passes when no job exists" do
      expect { refute_enqueued("email.send") }.not_to raise_error
    end

    it "refute_enqueued fails when job exists" do
      client.enqueue("email.send", to: "user@example.com")

      expect { refute_enqueued("email.send") }.to raise_error(RuntimeError, /Expected no/)
    end

    it "clear_all! removes all jobs" do
      client.enqueue("email.send", to: "user@example.com")
      clear_all!

      expect { assert_enqueued("email.send") }.to raise_error(RuntimeError)
    end
  end

  describe "drain" do
    it "processes jobs through registered handlers" do
      store = ojs_store
      store.record_enqueue("email.send", args: [{ "to" => "user@example.com" }])

      processed = false
      store.register_handler("email.send") { |_job| processed = true }

      drain

      expect(processed).to be true
      assert_performed "email.send"
      assert_completed "email.send"
    end

    it "marks failed jobs as discarded" do
      store = ojs_store
      store.record_enqueue("failing.job")
      store.register_handler("failing.job") { |_job| raise "boom" }

      drain

      assert_failed "failing.job"
    end

    it "respects max_jobs limit" do
      store = ojs_store
      3.times { store.record_enqueue("email.send") }

      processed = drain(max_jobs: 2)

      expect(processed).to eq(2)
    end
  end
end
