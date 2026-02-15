# frozen_string_literal: true

module OJS
  # A single step in a workflow (used in chain, group, or batch).
  class Step
    attr_reader :type, :args, :queue, :priority, :retry_policy, :timeout, :meta

    def initialize(type:, args: {}, queue: nil, priority: nil, retry_policy: nil, timeout: nil, meta: nil)
      @type = type
      @args = args
      @queue = queue
      @priority = priority
      @retry_policy = retry_policy
      @timeout = timeout
      @meta = meta
    end

    # Serialize to wire-format Hash.
    def to_hash
      h = {
        "type" => @type,
        "args" => wrap_args(@args),
      }
      h["queue"] = @queue if @queue
      h["priority"] = @priority if @priority
      h["retry"] = @retry_policy.to_hash if @retry_policy
      h["timeout"] = @timeout if @timeout
      h["meta"] = stringify_keys(@meta) if @meta && !@meta.empty?
      h
    end

    private

    def wrap_args(args)
      case args
      when Hash then [args.transform_keys(&:to_s)]
      when Array then args
      else [args]
      end
    end

    def stringify_keys(hash)
      hash.transform_keys(&:to_s)
    end
  end

  # Workflow definition for chain, group, or batch.
  class WorkflowDefinition
    attr_reader :workflow_type, :name, :steps, :callbacks

    def initialize(workflow_type:, name: nil, steps: [], callbacks: nil)
      @workflow_type = workflow_type
      @name = name
      @steps = steps
      @callbacks = callbacks
    end

    # Serialize to wire-format Hash.
    def to_hash
      h = { "type" => @workflow_type }
      h["name"] = @name if @name

      case @workflow_type
      when "chain"
        h["steps"] = @steps.map { |s| step_to_hash(s) }
      when "group"
        h["jobs"] = @steps.map { |s| step_to_hash(s) }
      when "batch"
        h["jobs"] = @steps.map { |s| step_to_hash(s) }
        if @callbacks
          cb = {}
          cb["on_complete"] = step_to_hash(@callbacks[:on_complete]) if @callbacks[:on_complete]
          cb["on_success"] = step_to_hash(@callbacks[:on_success]) if @callbacks[:on_success]
          cb["on_failure"] = step_to_hash(@callbacks[:on_failure]) if @callbacks[:on_failure]
          h["callbacks"] = cb unless cb.empty?
        end
      end

      h
    end

    private

    def step_to_hash(step)
      step.to_hash
    end
  end

  # Build a chain (sequential) workflow.
  #
  #   OJS.chain(
  #     OJS::Step.new(type: "data.fetch", args: { url: "..." }),
  #     OJS::Step.new(type: "data.transform", args: { format: "csv" }),
  #     name: "etl-pipeline"
  #   )
  def self.chain(*steps, name: nil)
    WorkflowDefinition.new(workflow_type: "chain", name: name, steps: steps)
  end

  # Build a group (parallel) workflow.
  #
  #   OJS.group(
  #     OJS::Step.new(type: "export.csv", args: { id: 1 }),
  #     OJS::Step.new(type: "export.pdf", args: { id: 1 }),
  #     name: "multi-export"
  #   )
  def self.group(*jobs, name: nil)
    WorkflowDefinition.new(workflow_type: "group", name: name, steps: jobs)
  end

  # Build a batch (parallel with callbacks) workflow.
  #
  #   OJS.batch(
  #     [OJS::Step.new(type: "email.send", args: { to: "a@b.com" })],
  #     name: "bulk-send",
  #     on_complete: OJS::Step.new(type: "batch.report", args: {}),
  #     on_success: OJS::Step.new(type: "batch.celebrate", args: {}),
  #     on_failure: OJS::Step.new(type: "batch.alert", args: {})
  #   )
  def self.batch(jobs, name: nil, on_complete: nil, on_success: nil, on_failure: nil)
    callbacks = nil
    if on_complete || on_success || on_failure
      callbacks = {
        on_complete: on_complete,
        on_success: on_success,
        on_failure: on_failure,
      }
    end
    WorkflowDefinition.new(workflow_type: "batch", name: name, steps: jobs, callbacks: callbacks)
  end
end
