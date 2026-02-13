# frozen_string_literal: true

module OJS
  # Queue statistics value object.
  class QueueStats
    attr_reader :name, :depth, :active, :scheduled, :retryable,
                :dead_letter, :paused, :created_at, :updated_at

    def initialize(name:, depth: 0, active: 0, scheduled: 0, retryable: 0,
                   dead_letter: 0, paused: false, created_at: nil, updated_at: nil)
      @name = name
      @depth = depth
      @active = active
      @scheduled = scheduled
      @retryable = retryable
      @dead_letter = dead_letter
      @paused = paused
      @created_at = created_at
      @updated_at = updated_at
    end

    def paused?
      @paused
    end

    # Build from a wire-format Hash.
    def self.from_hash(hash)
      hash = hash.transform_keys(&:to_s)
      new(
        name: hash["queue"] || hash["name"],
        depth: hash["depth"] || 0,
        active: hash["active"] || 0,
        scheduled: hash["scheduled"] || 0,
        retryable: hash["retryable"] || 0,
        dead_letter: hash["dead_letter"] || 0,
        paused: hash["paused"] || false,
        created_at: hash["created_at"],
        updated_at: hash["updated_at"],
      )
    end
  end
end
