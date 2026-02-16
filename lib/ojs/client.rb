# frozen_string_literal: true

require "set"
require "uri"

module OJS
  # OJS client for enqueuing jobs and managing queues.
  #
  #   client = OJS::Client.new("http://localhost:8080")
  #
  #   # Simple enqueue
  #   job = client.enqueue("email.send", to: "user@example.com")
  #
  #   # Enqueue with options
  #   job = client.enqueue("report.generate", { id: 42 },
  #     queue: "reports",
  #     delay: "5m",
  #     retry: OJS::RetryPolicy.new(max_attempts: 5),
  #     unique: OJS::UniquePolicy.new(key: ["id"], period: "1h")
  #   )
  #
  class Client
    # Keywords recognized as enqueue options (not job args).
    OPTION_KEYS = Set.new(%i[
      queue delay scheduled_at priority timeout meta expires_at
      retry unique schema
    ]).freeze

    # @param url [String] OJS server base URL
    # @param timeout [Integer] request timeout in seconds
    # @param headers [Hash] additional HTTP headers
    # @param transport [#post, #get, #delete, nil] optional custom transport (used by OJS::Testing)
    def initialize(url, timeout: 30, headers: {}, transport: nil)
      @transport = transport || Transport::HTTP.new(url, timeout: timeout, headers: headers)
    end

    # Close the underlying HTTP connection.
    # Call this when you are done using the client to release resources.
    def close
      @transport.close
    end

    # Enqueue a single job.
    #
    # Supports two calling styles:
    #   client.enqueue("email.send", to: "user@example.com")
    #   client.enqueue("report.generate", { id: 42 }, queue: "reports")
    #
    # @param type [String] dot-namespaced job type
    # @param args [Hash, Array, nil] job arguments (or pass as keyword args)
    # @param options [Hash] enqueue options and/or job args as keywords
    # @return [Job] the enqueued job
    # @raise [ArgumentError] if type is empty or nil
    def enqueue(type, args = nil, **options)
      validate_type!(type)
      opts, extra_args = split_options(options)

      # If no positional args given, use keyword args as the job payload
      args = extra_args if args.nil? && !extra_args.empty?
      args ||= {}

      job = build_job(type, args, opts)
      body = @transport.post("/jobs", body: job.to_hash)
      Job.from_hash(body)
    end

    # Enqueue multiple jobs atomically.
    #
    #   client.enqueue_batch([
    #     { type: "email.send", args: { to: "a@b.com" } },
    #     { type: "email.send", args: { to: "c@d.com" } },
    #   ])
    #
    # @param jobs [Array<Hash>] job specifications
    # @return [Array<Job>] the enqueued jobs
    def enqueue_batch(jobs)
      payload = jobs.map do |spec|
        spec = spec.transform_keys(&:to_sym)
        build_job(spec[:type], spec[:args] || {}, spec).to_hash
      end

      body = @transport.post("/jobs/batch", body: { "jobs" => payload })
      results = body.is_a?(Hash) ? (body["jobs"] || [body]) : Array(body)
      results.map { |j| Job.from_hash(j) }
    end

    # Create and start a workflow.
    #
    #   client.workflow(OJS.chain(
    #     OJS::Step.new(type: "data.fetch", args: { url: "..." }),
    #     OJS::Step.new(type: "data.transform", args: { format: "csv" }),
    #   ))
    #
    # @param definition [WorkflowDefinition] workflow built via OJS.chain/group/batch
    # @return [Hash] workflow response with ID and status
    def workflow(definition)
      body = @transport.post("/workflows", body: definition.to_hash)
      body
    end

    # Get a job by ID.
    #
    # @param id [String] job ID
    # @return [Job]
    # @raise [ArgumentError] if id is empty or contains path separators
    def get_job(id)
      body = @transport.get("/jobs/#{sanitize_id!(id)}")
      Job.from_hash(body)
    end

    # Cancel a job.
    #
    # @param id [String] job ID
    # @return [Hash] cancellation response
    # @raise [ArgumentError] if id is empty or contains path separators
    def cancel_job(id)
      @transport.delete("/jobs/#{sanitize_id!(id)}")
    end

    # ------------------------------------------------------------------
    # Queue operations
    # ------------------------------------------------------------------

    # List all queues.
    #
    # @return [Array<String>] queue names
    def queues
      body = @transport.get("/queues")
      body.is_a?(Hash) ? (body["queues"] || []) : Array(body)
    end

    # Get queue statistics.
    #
    # @param name [String] queue name
    # @return [QueueStats]
    def queue_stats(name)
      body = @transport.get("/queues/#{sanitize_id!(name)}/stats")
      QueueStats.from_hash(body)
    end

    # Pause a queue.
    #
    # @param name [String] queue name
    def pause_queue(name)
      @transport.post("/queues/#{sanitize_id!(name)}/pause")
    end

    # Resume a paused queue.
    #
    # @param name [String] queue name
    def resume_queue(name)
      @transport.post("/queues/#{sanitize_id!(name)}/resume")
    end

    # ------------------------------------------------------------------
    # Dead letter operations
    # ------------------------------------------------------------------

    # List dead letter jobs.
    #
    # @return [Array<Job>]
    def dead_letter_jobs
      body = @transport.get("/dead-letter")
      results = body.is_a?(Hash) ? (body["jobs"] || []) : Array(body)
      results.map { |j| Job.from_hash(j) }
    end

    # Retry a dead letter job.
    #
    # @param id [String] job ID
    # @return [Job]
    def retry_dead_letter(id)
      body = @transport.post("/dead-letter/#{sanitize_id!(id)}/retry")
      Job.from_hash(body)
    end

    # Discard a dead letter job.
    #
    # @param id [String] job ID
    def discard_dead_letter(id)
      @transport.delete("/dead-letter/#{sanitize_id!(id)}")
    end

    # ------------------------------------------------------------------
    # Cron operations
    # ------------------------------------------------------------------

    # List all registered cron jobs.
    #
    # @return [Array<Hash>] cron job entries
    def list_cron_jobs
      body = @transport.get("/cron")
      body.is_a?(Hash) ? (body["entries"] || []) : Array(body)
    end

    # Register a cron job.
    #
    # @param name [String] unique cron job name
    # @param cron [String] cron expression (e.g., "*/5 * * * *")
    # @param type [String] job type to enqueue
    # @param args [Array] job arguments (default: [])
    # @param options [Hash] additional fields (queue:, meta:, etc.)
    # @return [Hash] registered cron job
    def register_cron_job(name:, cron:, type:, args: [], **options)
      payload = { "name" => name, "cron" => cron, "type" => type, "args" => args }
      payload["queue"] = options[:queue].to_s if options[:queue]
      payload["meta"] = options[:meta] if options[:meta]
      @transport.post("/cron", body: payload)
    end

    # Unregister a cron job.
    #
    # @param name [String] cron job name
    # @return [Hash] deletion response
    def unregister_cron_job(name)
      @transport.delete("/cron/#{sanitize_id!(name)}")
    end

    # ------------------------------------------------------------------
    # Schema operations
    # ------------------------------------------------------------------

    # List all registered schemas.
    #
    # @return [Array<Hash>] schema entries
    def list_schemas
      body = @transport.get("/schemas")
      body.is_a?(Hash) ? (body["schemas"] || []) : Array(body)
    end

    # Register a schema.
    #
    # @param uri [String] schema URI
    # @param type [String] job type the schema applies to
    # @param version [String] schema version
    # @param schema [Hash] the schema definition
    # @return [Hash] registered schema
    def register_schema(uri:, type:, version:, schema:)
      payload = { "uri" => uri, "type" => type, "version" => version, "schema" => schema }
      @transport.post("/schemas", body: payload)
    end

    # Get a schema by URI.
    #
    # @param uri [String] schema URI
    # @return [Hash] schema definition
    def get_schema(uri)
      encoded = URI.encode_www_form_component(uri.to_s)
      @transport.get("/schemas/#{encoded}")
    end

    # Delete a schema by URI.
    #
    # @param uri [String] schema URI
    # @return [Hash] deletion response
    def delete_schema(uri)
      encoded = URI.encode_www_form_component(uri.to_s)
      @transport.delete("/schemas/#{encoded}")
    end

    # ------------------------------------------------------------------
    # Health & manifest
    # ------------------------------------------------------------------

    # Server health check.
    #
    # @return [Hash] health status
    def health
      @transport.get("/health")
    end

    # Get server manifest (capabilities, supported features).
    # Note: manifest lives at /ojs/manifest, not under /ojs/v1/.
    #
    # @return [Hash] server manifest
    def manifest
      @transport.get("/ojs/manifest", absolute: true)
    end

    # Get workflow status.
    #
    # @param id [String] workflow ID
    # @return [Hash]
    def get_workflow(id)
      @transport.get("/workflows/#{sanitize_id!(id)}")
    end

    # Cancel a workflow.
    #
    # @param id [String] workflow ID
    # @return [Hash]
    def cancel_workflow(id)
      @transport.delete("/workflows/#{sanitize_id!(id)}")
    end

    private

    # Separate known option keys from extra keyword args (which become job args).
    def split_options(kwargs)
      opts = {}
      extra = {}
      kwargs.each do |k, v|
        if OPTION_KEYS.include?(k)
          opts[k] = v
        else
          extra[k] = v
        end
      end
      [opts, extra]
    end

    # Build a Job from type, args, and options hash.
    def build_job(type, args, opts)
      scheduled_at = opts[:scheduled_at]

      # Convert delay shorthand to scheduled_at
      if opts[:delay] && scheduled_at.nil?
        seconds = parse_delay(opts[:delay])
        scheduled_at = (Time.now.utc + seconds).strftime("%Y-%m-%dT%H:%M:%SZ")
      end

      retry_policy = opts[:retry]
      retry_policy = RetryPolicy.new(**opts[:retry]) if retry_policy.is_a?(Hash)

      unique_policy = opts[:unique]
      unique_policy = UniquePolicy.new(**opts[:unique]) if unique_policy.is_a?(Hash)

      Job.new(
        type: type.to_s,
        args: args,
        queue: (opts[:queue] || "default").to_s,
        meta: opts[:meta],
        priority: opts[:priority],
        timeout: opts[:timeout],
        scheduled_at: scheduled_at,
        expires_at: opts[:expires_at],
        retry_policy: retry_policy,
        unique_policy: unique_policy,
        schema: opts[:schema],
      )
    end

    # Parse a human-friendly delay string or ISO 8601 duration to seconds.
    #
    # Delegates to RetryPolicy.parse_duration which supports:
    # "30s", "5m", "2h", "1d" and ISO 8601 "PT5M", "PT1H", etc.
    def parse_delay(delay)
      return delay if delay.is_a?(Numeric)

      RetryPolicy.parse_duration(delay.to_s)
    end

    # Validate that job type is a non-empty string.
    def validate_type!(type)
      raise ArgumentError, "job type must be a non-empty String" if type.nil? || type.to_s.strip.empty?
    end

    # Validate and sanitize an ID or name used in URL paths.
    # Prevents path traversal via embedded slashes or dot-dot sequences.
    def sanitize_id!(id)
      str = id.to_s
      raise ArgumentError, "id must be a non-empty String" if str.strip.empty?
      raise ArgumentError, "id must not contain path separators" if str.include?("/") || str.include?("\\")
      raise ArgumentError, "id must not contain path traversal" if str.include?("..")

      URI.encode_www_form_component(str)
    end
  end
end
