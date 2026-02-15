# frozen_string_literal: true

# OJS Testing Module — fake mode, assertions, and test utilities.
#
# Implements the OJS Testing Specification (ojs-testing.md).
#
# Usage with RSpec:
#
#   RSpec.describe UserSignup do
#     include OJS::Testing
#
#     before { ojs_fake! }
#     after  { ojs_restore! }
#
#     it "sends welcome email" do
#       client = OJS::Client.new("http://fake", transport: OJS::Testing.fake_transport)
#       client.enqueue("email.send", to: "user@example.com")
#       assert_enqueued "email.send", args: [{ "to" => "user@example.com" }]
#     end
#   end

module OJS
  module Testing
    # A job recorded in fake mode.
    FakeJob = Struct.new(:id, :type, :queue, :args, :meta, :state, :attempt, :options, :created_at, keyword_init: true) do
      def initialize(**)
        super
        self.queue ||= "default"
        self.args ||= []
        self.meta ||= {}
        self.state ||= "available"
        self.attempt ||= 0
        self.options ||= {}
        self.created_at ||= Time.now.utc.iso8601
      end
    end

    # In-memory store for fake mode.
    class FakeStore
      attr_reader :enqueued, :performed, :handlers

      def initialize
        @enqueued = []
        @performed = []
        @handlers = {}
        @next_id = 0
        @mutex = Mutex.new
      end

      def record_enqueue(type, args: [], queue: "default", meta: {}, options: {})
        @mutex.synchronize do
          @next_id += 1
          job = FakeJob.new(
            id: format("fake-%06d", @next_id),
            type: type,
            queue: queue,
            args: args,
            meta: meta,
            options: options
          )
          @enqueued << job
          job
        end
      end

      def register_handler(type, &block)
        @handlers[type] = block
      end

      def clear!
        @mutex.synchronize do
          @enqueued.clear
          @performed.clear
        end
      end

      def drain(max_jobs: nil)
        processed = 0
        limit = max_jobs || @enqueued.size

        @enqueued.each do |job|
          break if processed >= limit
          next unless job.state == "available"

          job.state = "active"
          job.attempt += 1
          handler = @handlers[job.type]

          if handler
            begin
              handler.call(job)
              job.state = "completed"
            rescue StandardError
              job.state = "discarded"
            end
          else
            job.state = "completed"
          end

          @performed << job
          processed += 1
        end

        processed
      end
    end

    # In-memory transport that records operations to the FakeStore.
    # Implements the same interface as Transport::HTTP (#post, #get, #delete, #close).
    class FakeTransport
      def initialize(store)
        @store = store
      end

      def post(path, body: nil)
        case path
        when "/jobs"
          record_job(body)
        when "/jobs/batch"
          jobs = (body["jobs"] || []).map { |j| record_job(j) }
          { "jobs" => jobs }
        when "/workflows"
          { "id" => "fake-wf-#{SecureRandom.hex(4)}", "type" => body["type"], "state" => "running" }
        when %r{\A/workers/}
          body || {}
        when %r{\A/queues/.+/pause\z}
          {}
        when %r{\A/queues/.+/resume\z}
          {}
        when %r{\A/dead-letter/.+/retry\z}
          { "id" => "fake-retry-#{SecureRandom.hex(4)}", "type" => "retried", "queue" => "default",
            "args" => [{}], "state" => "available" }
        else
          {}
        end
      end

      def get(path, params: {})
        case path
        when "/health"
          { "status" => "ok", "version" => OJS::SPEC_VERSION }
        when %r{\A/jobs/(.+)\z}
          id = URI.decode_www_form_component($1)
          job = @store.enqueued.find { |j| j.id == id }
          if job
            { "id" => job.id, "type" => job.type, "queue" => job.queue,
              "args" => job.args, "state" => job.state, "attempt" => job.attempt }
          else
            raise OJS::NotFoundError.new("Job not found")
          end
        when "/queues"
          queues = @store.enqueued.map(&:queue).uniq
          { "queues" => queues }
        when %r{\A/queues/(.+)/stats\z}
          queue_name = URI.decode_www_form_component($1)
          jobs = @store.enqueued.select { |j| j.queue == queue_name }
          { "queue" => queue_name, "depth" => jobs.size, "active" => 0, "paused" => false }
        when "/dead-letter"
          { "jobs" => [] }
        when %r{\A/workflows/(.+)\z}
          { "id" => URI.decode_www_form_component($1), "state" => "running" }
        else
          {}
        end
      end

      def delete(path)
        case path
        when %r{\A/jobs/(.+)\z}
          id = URI.decode_www_form_component($1)
          job = @store.enqueued.find { |j| j.id == id }
          job.state = "cancelled" if job
          { "status" => "cancelled" }
        when %r{\A/dead-letter/(.+)\z}
          {}
        when %r{\A/workflows/(.+)\z}
          { "status" => "cancelled" }
        else
          {}
        end
      end

      def close
        # No-op for fake transport
      end

      private

      def record_job(body)
        type = body["type"]
        args = body["args"] || [{}]
        queue = body["queue"] || "default"
        meta = body["meta"] || {}

        fake_job = @store.record_enqueue(type, args: args, queue: queue, meta: meta)

        {
          "specversion" => OJS::SPEC_VERSION,
          "id" => fake_job.id,
          "type" => type,
          "queue" => queue,
          "args" => args,
          "state" => "available",
          "attempt" => 0,
          "created_at" => fake_job.created_at,
        }
      end
    end

    @active_store = nil

    class << self
      attr_accessor :active_store

      # Returns a FakeTransport backed by the active store.
      # Use this when constructing an OJS::Client in tests.
      #
      # @return [FakeTransport]
      def fake_transport
        store = active_store
        raise "OJS testing: not in fake mode. Call ojs_fake! first." unless store

        FakeTransport.new(store)
      end
    end

    # Activate fake mode.
    def ojs_fake!
      OJS::Testing.active_store = FakeStore.new
    end

    # Restore real mode and clear state.
    def ojs_restore!
      OJS::Testing.active_store = nil
    end

    # Get the active fake store.
    def ojs_store
      store = OJS::Testing.active_store
      raise "OJS testing: not in fake mode. Call ojs_fake! first." unless store
      store
    end

    # Assert that at least one job of the given type was enqueued.
    def assert_enqueued(type, args: nil, queue: nil, meta: nil, count: nil)
      matches = find_matching(ojs_store.enqueued, type, args: args, queue: queue, meta: meta)

      if count
        unless matches.size == count
          enqueued_types = ojs_store.enqueued.map(&:type).uniq
          raise "Expected #{count} enqueued job(s) of type '#{type}', found #{matches.size}. Enqueued types: #{enqueued_types}"
        end
      elsif matches.empty?
        enqueued_types = ojs_store.enqueued.map(&:type).uniq
        raise "Expected at least one enqueued job of type '#{type}', found none. Enqueued types: #{enqueued_types.empty? ? 'none' : enqueued_types.join(', ')}"
      end
    end

    # Assert that NO job of the given type was enqueued.
    def refute_enqueued(type, args: nil, queue: nil, meta: nil)
      matches = find_matching(ojs_store.enqueued, type, args: args, queue: queue, meta: meta)
      unless matches.empty?
        raise "Expected no enqueued jobs of type '#{type}', but found #{matches.size}."
      end
    end

    # Assert that at least one job was performed.
    def assert_performed(type)
      match = ojs_store.performed.find { |j| j.type == type }
      raise "Expected at least one performed job of type '#{type}', found none." unless match
    end

    # Assert that at least one job completed.
    def assert_completed(type)
      match = ojs_store.performed.find { |j| j.type == type && j.state == "completed" }
      raise "Expected a completed job of type '#{type}', found none." unless match
    end

    # Assert that at least one job failed.
    def assert_failed(type)
      match = ojs_store.performed.find { |j| j.type == type && j.state == "discarded" }
      raise "Expected a failed job of type '#{type}', found none." unless match
    end

    # Return all enqueued jobs, optionally filtered.
    def all_enqueued(type: nil, queue: nil)
      jobs = ojs_store.enqueued
      jobs = jobs.select { |j| j.type == type } if type
      jobs = jobs.select { |j| j.queue == queue } if queue
      jobs
    end

    # Clear all enqueued and performed jobs.
    def clear_all!
      ojs_store.clear!
    end

    # Process all available jobs using registered handlers.
    def drain(max_jobs: nil)
      ojs_store.drain(max_jobs: max_jobs)
    end

    private

    def find_matching(jobs, type, args: nil, queue: nil, meta: nil)
      jobs.select do |j|
        next false unless j.type == type
        next false if queue && j.queue != queue
        next false if args && j.args != args
        if meta
          next false unless meta.all? { |k, v| j.meta[k] == v }
        end
        true
      end
    end
  end
end
