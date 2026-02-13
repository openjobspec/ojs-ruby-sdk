# frozen_string_literal: true

module OJS
  # Unique (deduplication) policy for jobs.
  class UniquePolicy
    attr_reader :keys, :args_keys, :meta_keys, :period, :states, :on_conflict

    DEFAULT_KEYS = ["type"].freeze
    DEFAULT_STATES = %w[available active scheduled retryable pending].freeze
    VALID_KEYS = %w[type queue args meta].freeze
    VALID_CONFLICTS = %w[reject replace replace_except_schedule ignore].freeze

    def initialize(
      keys: nil, key: nil, args_keys: nil, meta_keys: nil,
      period: nil, states: nil, on_conflict: "reject"
    )
      @keys = Array(keys || key || DEFAULT_KEYS).map(&:to_s)
      @args_keys = args_keys&.map(&:to_s)
      @meta_keys = meta_keys&.map(&:to_s)
      @period = period
      @states = states ? states.map(&:to_s) : DEFAULT_STATES.dup
      @on_conflict = on_conflict.to_s

      validate!
    end

    def inspect
      "#<OJS::UniquePolicy keys=#{@keys.inspect} on_conflict=#{@on_conflict.inspect}>"
    end

    # Build from a wire-format Hash.
    def self.from_hash(hash)
      return nil if hash.nil?

      hash = hash.transform_keys(&:to_s)
      new(
        keys: hash["keys"],
        args_keys: hash["args_keys"],
        meta_keys: hash["meta_keys"],
        period: hash["period"],
        states: hash["states"],
        on_conflict: hash["on_conflict"] || "reject",
      )
    end

    # Serialize to wire-format Hash.
    def to_hash
      h = { "keys" => @keys }
      h["args_keys"] = @args_keys if @args_keys
      h["meta_keys"] = @meta_keys if @meta_keys
      h["period"] = @period if @period
      h["states"] = @states if @states != DEFAULT_STATES
      h["on_conflict"] = @on_conflict if @on_conflict != "reject"
      h
    end

    private

    def validate!
      invalid_keys = @keys - VALID_KEYS
      unless invalid_keys.empty?
        raise ArgumentError, "Invalid unique keys: #{invalid_keys.join(", ")}. Valid: #{VALID_KEYS.join(", ")}"
      end

      if @keys.include?("meta") && (@meta_keys.nil? || @meta_keys.empty?)
        raise ArgumentError, "meta_keys required when 'meta' is included in keys"
      end

      unless VALID_CONFLICTS.include?(@on_conflict)
        raise ArgumentError, "Invalid on_conflict: #{@on_conflict}. Valid: #{VALID_CONFLICTS.join(", ")}"
      end
    end
  end
end
