# frozen_string_literal: true

require_relative "ojs/version"
require_relative "ojs/errors"
require_relative "ojs/error_codes"
require_relative "ojs/retry_policy"
require_relative "ojs/unique_policy"
require_relative "ojs/job"
require_relative "ojs/queue"
require_relative "ojs/workflow"
require_relative "ojs/middleware"
require_relative "ojs/events"
require_relative "ojs/transport/rate_limiter"
require_relative "ojs/transport/http"
require_relative "ojs/client"
require_relative "ojs/worker"

# Open Job Spec (OJS) SDK for Ruby.
#
# Quick start:
#
#   require "ojs"
#
#   # Enqueue a job
#   client = OJS::Client.new("http://localhost:8080")
#   job = client.enqueue("email.send", to: "user@example.com")
#
#   # Process jobs
#   worker = OJS::Worker.new("http://localhost:8080", queues: %w[default])
#   worker.register("email.send") { |ctx| send_email(ctx.job.args["to"]) }
#   worker.start
#
module OJS
  # Named priority levels (recommended by spec).
  module Priority
    HIGH   = 10
    NORMAL = 0
    LOW    = -10
  end

  # Job states as defined by the spec.
  module State
    SCHEDULED  = "scheduled"
    AVAILABLE  = "available"
    PENDING    = "pending"
    ACTIVE     = "active"
    COMPLETED  = "completed"
    RETRYABLE  = "retryable"
    CANCELLED  = "cancelled"
    DISCARDED  = "discarded"
  end
end
