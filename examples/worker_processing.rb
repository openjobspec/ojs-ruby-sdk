#!/usr/bin/env ruby
# frozen_string_literal: true

# Worker processing example using the OJS Ruby SDK.
#
# Prerequisites:
#   - An OJS-compatible server running at http://localhost:8080
#
# Run:
#   ruby examples/worker_processing.rb

require_relative "../lib/ojs"

worker = OJS::Worker.new("http://localhost:8080",
  queues: %w[default email reports],
  concurrency: 10,
  poll_interval: 1.0,
  shutdown_timeout: 30.0
)

# ------------------------------------------------------------------
# Register handlers
# ------------------------------------------------------------------

worker.register("email.send") do |ctx|
  to = ctx.job.args["to"]
  subject = ctx.job.args["subject"] || "Hello"

  # Simulate sending email
  puts "[email.send] Sending to #{to}: #{subject}"
  sleep(0.5)

  { message_id: "msg_#{SecureRandom.hex(8)}", status: "sent" }
end

worker.register("report.generate") do |ctx|
  report_id = ctx.job.args["report_id"]
  format = ctx.job.args["format"] || "pdf"

  puts "[report.generate] Generating report ##{report_id} as #{format}"

  # For long-running jobs, send heartbeats to extend the visibility timeout
  3.times do |i|
    sleep(1)
    ctx.heartbeat
    puts "  Progress: #{(i + 1) * 33}%"
  end

  { path: "/reports/#{report_id}.#{format}", size_bytes: 1024 }
end

worker.register("data.fetch") do |ctx|
  url = ctx.job.args["url"]
  puts "[data.fetch] Fetching #{url}"
  sleep(0.3)
  { rows: 1000, source: url }
end

worker.register("data.transform") do |ctx|
  format = ctx.job.args["format"]
  puts "[data.transform] Transforming to #{format}"
  sleep(0.2)
  { format: format, rows: 1000 }
end

# ------------------------------------------------------------------
# Middleware
# ------------------------------------------------------------------

# Logging middleware
worker.use("logging") do |ctx, &nxt|
  puts "[#{Time.now.strftime("%H:%M:%S")}] START #{ctx.job.type} (id: #{ctx.job.id}, attempt: #{ctx.job.attempt})"
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  result = nxt.call

  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  puts "[#{Time.now.strftime("%H:%M:%S")}] DONE  #{ctx.job.type} in #{elapsed.round(3)}s"
  result
end

# Error reporting middleware
worker.use("error_reporting") do |ctx, &nxt|
  nxt.call
rescue => e
  puts "[ERROR] #{ctx.job.type} failed: #{e.class}: #{e.message}"
  # Re-raise so the worker reports the failure
  raise
end

# Trace context middleware
worker.use("tracing") do |ctx, &nxt|
  trace_id = ctx.job.meta["trace_id"]
  if trace_id
    # In a real app, you'd set up your tracing context here
    ctx.store[:trace_id] = trace_id
    puts "  trace_id: #{trace_id}"
  end
  nxt.call
end

# ------------------------------------------------------------------
# Start worker (blocks until SIGTERM/SIGINT)
# ------------------------------------------------------------------
puts "Starting OJS worker..."
puts "  Queues: #{%w[default email reports].join(", ")}"
puts "  Concurrency: 10"
puts "  Press Ctrl+C to stop"
puts

worker.start
