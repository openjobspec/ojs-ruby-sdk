#!/usr/bin/env ruby
# frozen_string_literal: true

# Workflow example: chain, group, and batch.
#
# Demonstrates composing multi-step job workflows using OJS workflow
# primitives. Each primitive maps to a different execution strategy:
#
#   - Chain:  sequential (step N waits for step N-1)
#   - Group:  parallel   (all steps run concurrently)
#   - Batch:  parallel with callbacks (on_complete, on_success, on_failure)
#
# Prerequisites:
#   - An OJS-compatible server running at http://localhost:8080
#
# Run:
#   ruby examples/workflow_chain.rb

require_relative "../lib/ojs"

client = OJS::Client.new("http://localhost:8080")

# ------------------------------------------------------------------
# 1. Chain workflow: sequential execution
# ------------------------------------------------------------------
# Steps execute one after another: fetch → transform → notify.
# Each step receives the previous step's result as input.

result = client.workflow(OJS.chain(
  OJS::Step.new(type: "data.fetch", args: { url: "https://api.example.com/data" }),
  OJS::Step.new(type: "data.transform", args: { format: "csv" }),
  OJS::Step.new(type: "notification.send", args: { channel: "slack", message: "Data ready!" }),
  name: "etl-pipeline"
))
puts "Chain workflow created: #{result["id"]} (state: #{result["state"]})"

# ------------------------------------------------------------------
# 2. Group workflow: parallel execution
# ------------------------------------------------------------------
# All exports run simultaneously. The workflow completes when every
# step finishes.

result = client.workflow(OJS.group(
  OJS::Step.new(type: "export.csv", args: { report_id: "rpt_001" }),
  OJS::Step.new(type: "export.pdf", args: { report_id: "rpt_001" }),
  OJS::Step.new(type: "export.xlsx", args: { report_id: "rpt_001" }),
  name: "multi-format-export"
))
puts "Group workflow created: #{result["id"]} (state: #{result["state"]})"

# ------------------------------------------------------------------
# 3. Batch workflow: parallel with callbacks
# ------------------------------------------------------------------
# Jobs execute concurrently. Callbacks fire based on the collective
# outcome of all batch jobs.

result = client.workflow(OJS.batch(
  [
    OJS::Step.new(type: "email.send", args: { to: "user1@example.com", template: "promo" }),
    OJS::Step.new(type: "email.send", args: { to: "user2@example.com", template: "promo" }),
    OJS::Step.new(type: "email.send", args: { to: "user3@example.com", template: "promo" }),
  ],
  name: "email-campaign",
  on_complete: OJS::Step.new(type: "batch.report", args: { type: "email_campaign" }),
  on_success: OJS::Step.new(type: "batch.celebrate", args: {}),
  on_failure: OJS::Step.new(type: "batch.alert", args: { channel: "#ops", severity: "warning" })
))
puts "Batch workflow created: #{result["id"]} (state: #{result["state"]})"

# ------------------------------------------------------------------
# 4. Check workflow status
# ------------------------------------------------------------------

status = client.get_workflow(result["id"])
puts "\nWorkflow #{status["id"]}:"
puts "  State: #{status["state"]}"
(status["steps"] || []).each do |step|
  puts "  Step #{step["id"]} (#{step["type"]}): #{step["state"]}"
end

# ------------------------------------------------------------------
# 5. Cancel a workflow
# ------------------------------------------------------------------

cancelled = client.cancel_workflow(result["id"])
puts "\nWorkflow #{cancelled["id"]} cancelled"
