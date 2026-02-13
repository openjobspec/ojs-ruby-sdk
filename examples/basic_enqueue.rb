#!/usr/bin/env ruby
# frozen_string_literal: true

# Basic job enqueue example using the OJS Ruby SDK.
#
# Prerequisites:
#   - An OJS-compatible server running at http://localhost:8080
#
# Run:
#   ruby examples/basic_enqueue.rb

require_relative "../lib/ojs"

client = OJS::Client.new("http://localhost:8080")

# ------------------------------------------------------------------
# 1. Simple enqueue — keyword args become the job payload
# ------------------------------------------------------------------
job = client.enqueue("email.send", to: "user@example.com", subject: "Welcome!")
puts "Enqueued: #{job.id} (type: #{job.type}, queue: #{job.queue})"

# ------------------------------------------------------------------
# 2. Enqueue with explicit args hash and options
# ------------------------------------------------------------------
job = client.enqueue("report.generate", { report_id: 42, format: "pdf" },
  queue: "reports",
  priority: OJS::Priority::HIGH,
  delay: "5m",
  retry: OJS::RetryPolicy.new(max_attempts: 5, on_exhaustion: "dead_letter"),
  meta: { user_id: "usr_123", trace_id: "abc-def-ghi" }
)
puts "Scheduled: #{job.id} (scheduled_at: #{job.scheduled_at})"

# ------------------------------------------------------------------
# 3. Batch enqueue
# ------------------------------------------------------------------
recipients = %w[alice@example.com bob@example.com carol@example.com]
jobs = client.enqueue_batch(
  recipients.map { |email| { type: "email.send", args: { to: email } } }
)
puts "Batch enqueued: #{jobs.map(&:id).join(", ")}"

# ------------------------------------------------------------------
# 4. Enqueue with unique constraint
# ------------------------------------------------------------------
job = client.enqueue("invoice.generate",
  { customer_id: "cust_456", month: "2026-01" },
  unique: OJS::UniquePolicy.new(
    keys: ["type", "args"],
    args_keys: ["customer_id", "month"],
    period: "PT24H",
    on_conflict: "reject"
  )
)
puts "Unique job: #{job.id}"

# ------------------------------------------------------------------
# 5. Workflows
# ------------------------------------------------------------------

# Chain: sequential pipeline
result = client.workflow(OJS.chain(
  OJS::Step.new(type: "data.fetch", args: { url: "https://api.example.com/data" }),
  OJS::Step.new(type: "data.transform", args: { format: "csv" }),
  OJS::Step.new(type: "data.upload", args: { bucket: "results" }),
  name: "etl-pipeline"
))
puts "Chain workflow started: #{result["id"]}"

# Group: parallel execution
result = client.workflow(OJS.group(
  OJS::Step.new(type: "export.csv", args: { report_id: 1 }),
  OJS::Step.new(type: "export.pdf", args: { report_id: 1 }),
  OJS::Step.new(type: "export.xlsx", args: { report_id: 1 }),
  name: "multi-export"
))
puts "Group workflow started: #{result["id"]}"

# Batch: parallel with callbacks
result = client.workflow(OJS.batch(
  [
    OJS::Step.new(type: "email.send", args: { to: "a@example.com" }),
    OJS::Step.new(type: "email.send", args: { to: "b@example.com" }),
  ],
  name: "bulk-send",
  on_complete: OJS::Step.new(type: "batch.report", args: {}),
  on_failure: OJS::Step.new(type: "batch.alert", args: { channel: "#ops" })
))
puts "Batch workflow started: #{result["id"]}"

# ------------------------------------------------------------------
# 6. Job management
# ------------------------------------------------------------------
info = client.get_job(job.id)
puts "Job state: #{info.state}"

client.cancel_job(job.id)
puts "Job cancelled"

# ------------------------------------------------------------------
# 7. Queue operations
# ------------------------------------------------------------------
stats = client.queue_stats("default")
puts "Queue depth: #{stats.depth}, active: #{stats.active}"

# ------------------------------------------------------------------
# 8. Health check
# ------------------------------------------------------------------
health = client.health
puts "Server status: #{health["status"]}"
