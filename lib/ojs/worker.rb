# frozen_string_literal: true

module OJS
  # Context object passed to job handlers and middleware.
  class JobContext
    # @return [Job] the current job
    attr_reader :job

    # @return [Hash] mutable store for passing data through middleware
    attr_reader :store

    def initialize(job:, worker:)
      @job = job
      @worker = worker
      @store = {}
    end

    # Send a heartbeat to extend the visibility timeout for this job.
    def heartbeat
      @worker.send(:send_heartbeat, [@job.id])
    end
  end

  # OJS worker for consuming and processing jobs.
  #
  #   worker = OJS::Worker.new("http://localhost:8080",
  #     queues: %w[default email],
  #     concurrency: 10
  #   )
  #
  #   worker.register("email.send") do |ctx|
  #     send_email(ctx.job.args["to"])
  #     { message_id: "..." }
  #   end
  #
  #   worker.use do |ctx, &nxt|
  #     puts "Processing #{ctx.job.type}"
  #     nxt.call
  #   end
  #
  #   worker.start
  #
  class Worker
    # Default number of jobs to fetch per poll.
    DEFAULT_BATCH_SIZE = 5

    # Default poll interval in seconds when no jobs are available.
    DEFAULT_POLL_INTERVAL = 2.0

    # Default heartbeat interval in seconds.
    DEFAULT_HEARTBEAT_INTERVAL = 15.0

    # Default graceful shutdown timeout in seconds.
    DEFAULT_SHUTDOWN_TIMEOUT = 25.0

    # @param url [String] OJS server base URL
    # @param queues [Array<String>] queues to consume from
    # @param concurrency [Integer] number of worker threads
    # @param poll_interval [Numeric] seconds between polls when idle
    # @param heartbeat_interval [Numeric] seconds between heartbeats
    # @param shutdown_timeout [Numeric] seconds to wait for in-flight jobs on shutdown
    # @param timeout [Integer] HTTP request timeout in seconds
    # @param headers [Hash] additional HTTP headers
    def initialize(url, queues: ["default"], concurrency: 5, poll_interval: DEFAULT_POLL_INTERVAL,
                   heartbeat_interval: DEFAULT_HEARTBEAT_INTERVAL, shutdown_timeout: DEFAULT_SHUTDOWN_TIMEOUT,
                   timeout: 30, headers: {})
      @transport = Transport::HTTP.new(url, timeout: timeout, headers: headers)
      @queues = Array(queues)
      @concurrency = concurrency
      @poll_interval = poll_interval
      @heartbeat_interval = heartbeat_interval
      @shutdown_timeout = shutdown_timeout

      @handlers = {}
      @middleware = MiddlewareChain.new
      @state = :stopped  # :stopped, :running, :quiet, :terminating
      @mutex = Mutex.new
      @active_jobs = {}  # job_id => Thread
      @work_queue = Queue.new
      @threads = []
    end

    # Register a handler for a job type.
    #
    #   worker.register("email.send") do |ctx|
    #     send_email(ctx.job.args["to"])
    #     { status: "sent" }
    #   end
    #
    # @param type [String] dot-namespaced job type
    # @yield [ctx] handler block receiving a JobContext
    # @return [self]
    def register(type, &handler)
      raise ArgumentError, "handler block required" unless handler

      @handlers[type.to_s] = handler
      self
    end

    # Add a middleware to the execution chain.
    #
    #   worker.use("logging") do |ctx, &nxt|
    #     start = Time.now
    #     result = nxt.call
    #     puts "#{ctx.job.type} took #{Time.now - start}s"
    #     result
    #   end
    #
    # @param name [String, nil] optional middleware name
    # @yield [ctx, &next_handler] middleware block
    # @return [self]
    def use(name = nil, &block)
      @middleware.add(name, &block)
      self
    end

    # Access the middleware chain for advanced manipulation.
    #
    # @return [MiddlewareChain]
    attr_reader :middleware

    # Start the worker. Blocks the current thread until stopped.
    #
    # Installs signal handlers for SIGTERM (stop) and SIGINT (stop)
    # unless running in a non-main thread.
    def start
      @mutex.synchronize do
        raise "Worker already running" unless @state == :stopped

        @state = :running
      end

      install_signal_handlers if Thread.current == Thread.main

      # Start worker threads
      @concurrency.times do |i|
        @threads << Thread.new { worker_loop(i) }
      end

      # Start heartbeat thread
      @heartbeat_thread = Thread.new { heartbeat_loop }

      # Poll loop runs in current thread
      poll_loop
    ensure
      wait_for_shutdown
    end

    # Initiate graceful shutdown: stop fetching, finish in-flight jobs.
    def stop
      @mutex.synchronize do
        return if @state == :stopped || @state == :terminating

        @state = :terminating
      end
    end

    # Enter quiet mode: stop fetching new jobs but keep processing in-flight ones.
    def quiet
      @mutex.synchronize do
        return unless @state == :running

        @state = :quiet
      end
    end

    # Current worker state.
    #
    # @return [Symbol] :stopped, :running, :quiet, or :terminating
    def state
      @mutex.synchronize { @state }
    end

    private

    # Main poll loop — fetches jobs from the server and pushes to the work queue.
    def poll_loop
      while running_or_quiet?
        if should_fetch?
          jobs = fetch_jobs
          jobs.each { |job| @work_queue.push(job) } if jobs
        end
        sleep(@poll_interval) if running_or_quiet?
      end
    end

    # Worker thread loop — pulls jobs from the work queue and processes them.
    def worker_loop(_index)
      while running_or_processing?
        job = nil
        begin
          # Non-blocking pop with timeout to allow shutdown checks
          job = @work_queue.pop(true)
        rescue ThreadError
          # Queue empty
          sleep(0.1)
          next
        end

        break if job.nil?

        process_job(job)
      end
    end

    # Heartbeat loop — periodically sends heartbeats for active jobs.
    def heartbeat_loop
      while running_or_processing?
        sleep(@heartbeat_interval)
        job_ids = @mutex.synchronize { @active_jobs.keys.dup }
        send_heartbeat(job_ids) unless job_ids.empty?
      end
    end

    # Process a single job through middleware and handler.
    def process_job(job)
      @mutex.synchronize { @active_jobs[job.id] = Thread.current }

      handler = @handlers[job.type]
      unless handler
        nack_job(job.id, {
          "type" => "HandlerNotFound",
          "message" => "No handler registered for job type: #{job.type}",
        })
        return
      end

      ctx = JobContext.new(job: job, worker: self)

      result = @middleware.invoke(ctx) { handler.call(ctx) }
      ack_job(job.id, result)
    rescue => e
      nack_job(job.id, error_to_hash(e))
    ensure
      @mutex.synchronize { @active_jobs.delete(job.id) }
    end

    # Fetch jobs from the server.
    def fetch_jobs
      slots = @concurrency - @work_queue.size
      return [] if slots <= 0

      batch_size = [slots, DEFAULT_BATCH_SIZE].min
      body = @transport.post("/workers/fetch", body: {
        "queues" => @queues,
        "batch_size" => batch_size,
      })

      jobs = body.is_a?(Hash) ? (body["jobs"] || [body]) : Array(body)
      jobs.compact.map { |j| Job.from_hash(j) }
    rescue OJS::Error => e
      # Log and continue on fetch errors
      warn "[OJS::Worker] Fetch error: #{e.message}"
      []
    end

    # Acknowledge successful job completion.
    def ack_job(id, result)
      payload = { "job_id" => id }
      payload["result"] = result unless result.nil?
      @transport.post("/workers/ack", body: payload)
    rescue OJS::Error => e
      warn "[OJS::Worker] ACK error for job #{id}: #{e.message}"
    end

    # Report job failure.
    def nack_job(id, error)
      @transport.post("/workers/nack", body: {
        "job_id" => id,
        "error" => error,
      })
    rescue OJS::Error => e
      warn "[OJS::Worker] NACK error for job #{id}: #{e.message}"
    end

    # Send heartbeat for active jobs.
    def send_heartbeat(job_ids)
      @transport.post("/workers/heartbeat", body: {
        "job_ids" => job_ids,
      })
    rescue OJS::Error => e
      warn "[OJS::Worker] Heartbeat error: #{e.message}"
    end

    # Convert a Ruby exception to a wire-format error hash.
    def error_to_hash(exception)
      h = {
        "type" => exception.class.name || "RuntimeError",
        "message" => exception.message,
      }

      backtrace = exception.backtrace
      if backtrace && !backtrace.empty?
        h["backtrace"] = backtrace.first(50)
      end

      h
    end

    # Install signal handlers for graceful shutdown.
    def install_signal_handlers
      %w[TERM INT].each do |sig|
        Signal.trap(sig) { stop }
      end
    end

    # Wait for in-flight jobs to complete on shutdown.
    def wait_for_shutdown
      # Signal worker threads to stop
      @concurrency.times { @work_queue.push(nil) }

      # Wait for worker threads with timeout
      deadline = Time.now + @shutdown_timeout
      @threads.each do |t|
        remaining = deadline - Time.now
        t.join([remaining, 0].max)
      end

      # Wait for heartbeat thread
      @heartbeat_thread&.join(1)

      @mutex.synchronize do
        @state = :stopped
        @threads.clear
        @active_jobs.clear
      end
    end

    def running_or_quiet?
      s = @mutex.synchronize { @state }
      s == :running || s == :quiet
    end

    def running_or_processing?
      s = @mutex.synchronize { @state }
      s == :running || s == :quiet || (s == :terminating && !@active_jobs.empty?)
    end

    def should_fetch?
      @mutex.synchronize { @state == :running }
    end
  end
end
