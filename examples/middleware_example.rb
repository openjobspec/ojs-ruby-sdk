#!/usr/bin/env ruby
# frozen_string_literal: true

# Middleware example: logging, metrics, and trace-context middleware.
#
# Demonstrates the composable middleware pattern with &nxt blocks.
# Middleware wraps job handlers in an onion model — first-registered middleware
# executes outermost.
#
# Execution order for [logging, metrics, tracing]:
#   logging.before → metrics.before → tracing.before → handler
#   → tracing.after → metrics.after → logging.after
#
# Prerequisites:
#   - An OJS-compatible server running at http://localhost:8080
#
# Run:
#   ruby examples/middleware_example.rb

require_relative "../lib/ojs"

# ------------------------------------------------------------------
# Client-side: inject trace context when enqueuing
# ------------------------------------------------------------------
# Note: The Ruby SDK does not have a client-side middleware chain.
# Use a helper method to wrap enqueue calls instead.

client = OJS::Client.new("http://localhost:8080")

def enqueue_with_trace(client, type, args = {}, **opts)
  trace_id = "trace_#{SecureRandom.hex(8)}"

  meta = (opts.delete(:meta) || {}).merge(
    "trace_id" => trace_id,
    "enqueued_by" => "my-service",
    "enqueued_at_utc" => Time.now.utc.iso8601
  )

  puts "[enqueue] Submitting #{type} with trace_id=#{trace_id}"
  job = client.enqueue(type, args, meta: meta, **opts)
  puts "[enqueue] Created #{job.id} (state: #{job.state})"
  job
end

job = enqueue_with_trace(client, "email.send",
  { to: "user@example.com", subject: "Hello from middleware example" },
  queue: "email"
)

# ------------------------------------------------------------------
# Worker-side: composable middleware chain
# ------------------------------------------------------------------

worker = OJS::Worker.new("http://localhost:8080",
  queues: %w[default email],
  concurrency: 10,
  poll_interval: 1.0,
  shutdown_timeout: 30.0
)

# ------------------------------------------------------------------
# Middleware (outermost → innermost)
# ------------------------------------------------------------------

# 1. Logging middleware (outermost — wraps the entire execution chain)
worker.use("logging") do |ctx, &nxt|
  puts "[logging] Starting #{ctx.job.type} (id: #{ctx.job.id}, attempt: #{ctx.job.attempt})"
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  begin
    result = nxt.call
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    puts "[logging] Completed #{ctx.job.type} in #{(elapsed * 1000).round(1)}ms"
    result
  rescue => e
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    puts "[logging] Failed #{ctx.job.type} after #{(elapsed * 1000).round(1)}ms: #{e.message}"
    raise
  end
end

# 2. Metrics middleware (tracks counters and durations)
completed_count = 0
failed_count = 0
metrics_mutex = Mutex.new

worker.use("metrics") do |ctx, &nxt|
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  begin
    result = nxt.call
    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round(1)
    total = metrics_mutex.synchronize { completed_count += 1 }
    puts "[metrics] ojs.jobs.completed type=#{ctx.job.type} queue=#{ctx.job.queue} " \
         "duration=#{duration_ms}ms total=#{total}"
    result
  rescue => e
    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round(1)
    total = metrics_mutex.synchronize { failed_count += 1 }
    puts "[metrics] ojs.jobs.failed type=#{ctx.job.type} queue=#{ctx.job.queue} " \
         "duration=#{duration_ms}ms total=#{total}"
    raise
  end
end

# 3. Trace context middleware (innermost — restores distributed trace)
worker.use("trace-context") do |ctx, &nxt|
  trace_id = ctx.job.meta["trace_id"]
  if trace_id
    # In a real app, restore OpenTelemetry span context here.
    ctx.store[:trace_id] = trace_id
    puts "[trace] Restoring trace context: #{trace_id}"
  end
  nxt.call
end

# ------------------------------------------------------------------
# Register handlers
# ------------------------------------------------------------------

worker.register("email.send") do |ctx|
  to = ctx.job.args["to"]
  subject = ctx.job.args["subject"] || "No Subject"
  puts "  Sending email to #{to}: #{subject}"
  sleep(0.1)
  { message_id: "msg_#{SecureRandom.hex(8)}", delivered: true }
end

worker.register("report.generate") do |ctx|
  report_id = ctx.job.args["report_id"]
  puts "  Generating report ##{report_id}"

  3.times do |i|
    sleep(0.2)
    ctx.heartbeat
    puts "  Report ##{report_id} progress: #{(i + 1) * 33}%"
  end

  { path: "/reports/#{report_id}.pdf", size_bytes: 2048 }
end

# ------------------------------------------------------------------
# Start worker (blocks until SIGTERM/SIGINT)
# ------------------------------------------------------------------

puts "Starting worker with middleware chain: logging → metrics → trace-context"
puts "  Queues: #{%w[default email].join(", ")}"
puts "  Concurrency: 10"
puts "  Press Ctrl+C to stop"
puts

worker.start
