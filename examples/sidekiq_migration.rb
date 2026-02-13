#!/usr/bin/env ruby
# frozen_string_literal: true

# ==========================================================================
# Sidekiq to OJS Migration Guide
# ==========================================================================
#
# This guide shows how to migrate common Sidekiq patterns to OJS.
# OJS is a protocol-based job system — your workers communicate with an
# OJS-compatible server over HTTP, so you're no longer coupled to Redis
# or a specific Ruby framework.
#
# Key differences:
#   - Jobs are defined by type strings, not Ruby classes
#   - Arguments are a Hash (not positional array)
#   - Workers are registered with blocks, not classes with #perform
#   - Middleware uses &next block instead of yield
#   - No Redis dependency — any OJS-compatible backend works
#
# ==========================================================================

require_relative "../lib/ojs"

# ==========================================================================
# 1. DEFINING JOBS
# ==========================================================================

# ---- Sidekiq ----
#
#   class EmailWorker
#     include Sidekiq::Worker
#     sidekiq_options queue: :email, retry: 5
#
#     def perform(to, subject, body)
#       Mailer.send(to: to, subject: subject, body: body)
#     end
#   end
#
# ---- OJS ----
#
# No class needed. Register a handler block with the worker:

worker = OJS::Worker.new("http://localhost:8080",
  queues: %w[default email],
  concurrency: 10
)

worker.register("email.send") do |ctx|
  to      = ctx.job.args["to"]
  subject = ctx.job.args["subject"]
  body    = ctx.job.args["body"]

  # Mailer.send(to: to, subject: subject, body: body)
  puts "Sending email to #{to}"
  { status: "sent" }
end

# ==========================================================================
# 2. ENQUEUING JOBS
# ==========================================================================

# ---- Sidekiq ----
#
#   EmailWorker.perform_async("user@example.com", "Welcome", "Hello!")
#   EmailWorker.perform_in(5.minutes, "user@example.com", "Reminder", "...")
#   EmailWorker.perform_at(2.hours.from_now, "user@example.com", "Later", "...")
#
# ---- OJS ----

client = OJS::Client.new("http://localhost:8080")

# perform_async equivalent
client.enqueue("email.send",
  to: "user@example.com",
  subject: "Welcome",
  body: "Hello!"
)

# perform_in equivalent — use delay:
client.enqueue("email.send",
  { to: "user@example.com", subject: "Reminder", body: "..." },
  delay: "5m"
)

# perform_at equivalent — use scheduled_at:
client.enqueue("email.send",
  { to: "user@example.com", subject: "Later", body: "..." },
  scheduled_at: "2026-03-01T09:00:00Z"
)

# ==========================================================================
# 3. RETRY CONFIGURATION
# ==========================================================================

# ---- Sidekiq ----
#
#   class ImportWorker
#     include Sidekiq::Worker
#     sidekiq_options retry: 5
#     sidekiq_retry_in { |count| 10 * (count + 1) }  # linear backoff
#
#     def perform(file_path)
#       import(file_path)
#     end
#   end
#
# ---- OJS ----

client.enqueue("import.process", { file_path: "/uploads/data.csv" },
  retry: OJS::RetryPolicy.new(
    max_attempts: 5,
    initial_interval: "PT10S",      # Start at 10s
    backoff_coefficient: 2.0,       # Exponential: 10s, 20s, 40s, 80s, 160s
    max_interval: "PT10M",          # Cap at 10 minutes
    jitter: true,                   # Prevent thundering herd
    on_exhaustion: "dead_letter"    # Move to DLQ when retries exhausted
  )
)

# ==========================================================================
# 4. UNIQUE JOBS
# ==========================================================================

# ---- Sidekiq (with sidekiq-unique-jobs gem) ----
#
#   class ReportWorker
#     include Sidekiq::Worker
#     sidekiq_options lock: :until_executed,
#                     lock_timeout: 3600
#
#     def perform(report_id)
#       generate_report(report_id)
#     end
#   end
#
# ---- OJS ----
# Built-in, no extra gem needed:

client.enqueue("report.generate", { report_id: 42 },
  unique: OJS::UniquePolicy.new(
    keys: ["type", "args"],
    args_keys: ["report_id"],    # Only report_id matters for uniqueness
    period: "PT1H",              # Unique window: 1 hour
    on_conflict: "reject"        # Reject duplicates (409 response)
  )
)

# ==========================================================================
# 5. MIDDLEWARE
# ==========================================================================

# ---- Sidekiq ----
#
#   class LoggingMiddleware
#     def call(worker, msg, queue)
#       start = Time.now
#       yield                        # <-- Sidekiq uses yield
#       puts "Done in #{Time.now - start}s"
#     end
#   end
#
#   Sidekiq.configure_server do |config|
#     config.server_middleware do |chain|
#       chain.add LoggingMiddleware
#     end
#   end
#
# ---- OJS ----
# Similar pattern, but uses &next block instead of yield:

worker.use("logging") do |ctx, &nxt|
  start = Time.now
  result = nxt.call             # <-- OJS uses nxt.call
  puts "#{ctx.job.type} done in #{Time.now - start}s"
  result
end

# Error reporting middleware
worker.use("error_reporting") do |ctx, &nxt|
  nxt.call
rescue => e
  # Report to your error tracker
  # Honeybadger.notify(e, context: { job_type: ctx.job.type, job_id: ctx.job.id })
  puts "Error in #{ctx.job.type}: #{e.message}"
  raise  # Re-raise to trigger retry
end

# ==========================================================================
# 6. BATCH JOBS
# ==========================================================================

# ---- Sidekiq Pro ----
#
#   batch = Sidekiq::Batch.new
#   batch.on(:complete, 'BatchCallback#on_complete')
#   batch.jobs do
#     100.times { |i| EmailWorker.perform_async("user#{i}@example.com") }
#   end
#
# ---- OJS ----
# Built-in, no Pro license needed:

emails = (1..100).map do |i|
  OJS::Step.new(type: "email.send", args: { to: "user#{i}@example.com" })
end

client.workflow(OJS.batch(emails,
  name: "bulk-welcome-emails",
  on_complete: OJS::Step.new(type: "batch.report", args: { batch_name: "welcome" }),
  on_success: OJS::Step.new(type: "batch.celebrate", args: {}),
  on_failure: OJS::Step.new(type: "batch.alert", args: { channel: "#ops" })
))

# ==========================================================================
# 7. JOB CHAINS / WORKFLOWS
# ==========================================================================

# ---- Sidekiq (manual chaining or sidekiq-workflow gem) ----
#
#   # Typically done manually:
#   class StepOneWorker
#     def perform(data)
#       result = process(data)
#       StepTwoWorker.perform_async(result)
#     end
#   end
#
# ---- OJS ----
# First-class chain support with automatic result passing:

client.workflow(OJS.chain(
  OJS::Step.new(type: "order.validate", args: { order_id: "ord_123" }),
  OJS::Step.new(type: "payment.charge", args: {}),      # receives validate result
  OJS::Step.new(type: "inventory.reserve", args: {}),    # receives charge result
  OJS::Step.new(type: "notification.send", args: {}),    # receives reserve result
  name: "order-processing"
))

# ==========================================================================
# 8. QUEUE MANAGEMENT
# ==========================================================================

# ---- Sidekiq ----
#
#   Sidekiq::Queue.new("email").size
#   Sidekiq::Queue.new("email").clear
#
# ---- OJS ----

stats = client.queue_stats("email")
puts "Queue depth: #{stats.depth}"
puts "Active jobs: #{stats.active}"
puts "Paused: #{stats.paused?}"

# Pause/resume (no Sidekiq equivalent without Enterprise)
client.pause_queue("email")
client.resume_queue("email")

# ==========================================================================
# 9. DEAD LETTER QUEUE
# ==========================================================================

# ---- Sidekiq ----
#
#   Sidekiq::DeadSet.new.each { |job| job.retry }
#
# ---- OJS ----

dead_jobs = client.dead_letter_jobs
dead_jobs.each do |job|
  puts "Dead job: #{job.type} (#{job.id})"
  client.retry_dead_letter(job.id)
end

# ==========================================================================
# 10. STARTING THE WORKER
# ==========================================================================

# ---- Sidekiq ----
#
#   # Typically: bundle exec sidekiq -q default -q email -c 10
#
# ---- OJS ----
#
# Register all your handlers, then:
#
#   worker.start   # Blocks, handles SIGTERM/SIGINT gracefully
#
# Or in a script:
#
#   ruby examples/worker_processing.rb

# ==========================================================================
# CHEAT SHEET
# ==========================================================================
#
# | Sidekiq                          | OJS                                              |
# |----------------------------------|--------------------------------------------------|
# | `include Sidekiq::Worker`        | `worker.register("type") { |ctx| ... }`          |
# | `perform_async(a, b)`            | `client.enqueue("type", a: 1, b: 2)`             |
# | `perform_in(5.minutes, ...)`     | `client.enqueue("type", args, delay: "5m")`      |
# | `perform_at(time, ...)`          | `client.enqueue("type", args, scheduled_at: t)`  |
# | `sidekiq_options retry: 5`       | `retry: RetryPolicy.new(max_attempts: 5)`        |
# | `sidekiq_options queue: :email`  | `queue: "email"`                                 |
# | `Sidekiq::Batch` (Pro)           | `OJS.batch(jobs, on_complete: ...)`               |
# | `yield` (middleware)             | `nxt.call` (middleware)                           |
# | `Sidekiq::Queue.new(q).size`    | `client.queue_stats(q).depth`                    |
# | Redis required                   | Any OJS-compatible backend                       |
# | `bundle exec sidekiq`            | `worker.start`                                   |
