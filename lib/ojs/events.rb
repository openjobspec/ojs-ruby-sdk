# frozen_string_literal: true

module OJS
  # Standard OJS event type constants.
  module Events
    # Core job events (Level 0)
    JOB_ENQUEUED  = "job.enqueued"
    JOB_STARTED   = "job.started"
    JOB_COMPLETED = "job.completed"
    JOB_FAILED    = "job.failed"
    JOB_DISCARDED = "job.discarded"

    # Extended job events (Level 1+)
    JOB_RETRYING  = "job.retrying"
    JOB_CANCELLED = "job.cancelled"
    JOB_HEARTBEAT = "job.heartbeat"

    # Level 2
    JOB_SCHEDULED = "job.scheduled"
    JOB_EXPIRED   = "job.expired"

    # Level 3
    JOB_PROGRESS  = "job.progress"

    # Queue events (Level 4)
    QUEUE_PAUSED  = "queue.paused"
    QUEUE_RESUMED = "queue.resumed"

    # Worker events
    WORKER_STARTED   = "worker.started"
    WORKER_STOPPED   = "worker.stopped"
    WORKER_QUIET     = "worker.quiet"
    WORKER_HEARTBEAT = "worker.heartbeat"

    # Workflow events (Level 3+)
    WORKFLOW_STARTED        = "workflow.started"
    WORKFLOW_STEP_COMPLETED = "workflow.step_completed"
    WORKFLOW_COMPLETED      = "workflow.completed"
    WORKFLOW_FAILED         = "workflow.failed"

    # Cron events (Level 2+)
    CRON_TRIGGERED = "cron.triggered"
    CRON_SKIPPED   = "cron.skipped"
  end

  # An OJS event (CloudEvents-compatible envelope).
  class Event
    attr_reader :id, :type, :source, :time, :subject, :data

    def initialize(type:, data:, id: nil, source: nil, time: nil, subject: nil)
      @id = id
      @type = type
      @source = source
      @time = time || Time.now.utc.iso8601(3)
      @subject = subject
      @data = data
    end

    # Build from a parsed JSON hash.
    def self.from_hash(hash)
      hash = hash.transform_keys(&:to_s)
      new(
        id: hash["id"],
        type: hash["type"],
        source: hash["source"],
        time: hash["time"],
        subject: hash["subject"],
        data: hash["data"],
      )
    end
  end
end
