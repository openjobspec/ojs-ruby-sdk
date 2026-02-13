# frozen_string_literal: true

module OJS
  # Retry policy configuration for job failure handling.
  #
  # Durations use ISO 8601 format (e.g., "PT1S", "PT5M").
  class RetryPolicy
    attr_reader :max_attempts, :initial_interval, :backoff_coefficient,
                :max_interval, :jitter, :non_retryable_errors, :on_exhaustion

    DEFAULTS = {
      max_attempts: 3,
      initial_interval: "PT1S",
      backoff_coefficient: 2.0,
      max_interval: "PT5M",
      jitter: true,
      non_retryable_errors: [],
      on_exhaustion: "discard",
    }.freeze

    def initialize(
      max_attempts: DEFAULTS[:max_attempts],
      initial_interval: DEFAULTS[:initial_interval],
      backoff_coefficient: DEFAULTS[:backoff_coefficient],
      max_interval: DEFAULTS[:max_interval],
      jitter: DEFAULTS[:jitter],
      non_retryable_errors: DEFAULTS[:non_retryable_errors],
      on_exhaustion: DEFAULTS[:on_exhaustion]
    )
      @max_attempts = max_attempts
      @initial_interval = initial_interval
      @backoff_coefficient = backoff_coefficient.to_f
      @max_interval = max_interval
      @jitter = jitter
      @non_retryable_errors = Array(non_retryable_errors)
      @on_exhaustion = on_exhaustion

      validate!
    end

    # Build from a wire-format Hash.
    def self.from_hash(hash)
      return nil if hash.nil?

      hash = hash.transform_keys(&:to_s)
      new(
        max_attempts: hash["max_attempts"] || DEFAULTS[:max_attempts],
        initial_interval: hash["initial_interval"] || DEFAULTS[:initial_interval],
        backoff_coefficient: hash["backoff_coefficient"] || DEFAULTS[:backoff_coefficient],
        max_interval: hash["max_interval"] || DEFAULTS[:max_interval],
        jitter: hash.key?("jitter") ? hash["jitter"] : DEFAULTS[:jitter],
        non_retryable_errors: hash["non_retryable_errors"] || DEFAULTS[:non_retryable_errors],
        on_exhaustion: hash["on_exhaustion"] || DEFAULTS[:on_exhaustion],
      )
    end

    # Serialize to wire-format Hash.
    def to_hash
      h = { "max_attempts" => @max_attempts }
      h["initial_interval"] = @initial_interval if @initial_interval != DEFAULTS[:initial_interval]
      h["backoff_coefficient"] = @backoff_coefficient if @backoff_coefficient != DEFAULTS[:backoff_coefficient]
      h["max_interval"] = @max_interval if @max_interval != DEFAULTS[:max_interval]
      h["jitter"] = @jitter unless @jitter == DEFAULTS[:jitter]
      h["non_retryable_errors"] = @non_retryable_errors unless @non_retryable_errors.empty?
      h["on_exhaustion"] = @on_exhaustion if @on_exhaustion != DEFAULTS[:on_exhaustion]
      h
    end

    def inspect
      "#<OJS::RetryPolicy max_attempts=#{@max_attempts} backoff=#{@backoff_coefficient}x on_exhaustion=#{@on_exhaustion.inspect}>"
    end

    # Compute the backoff delay in seconds for a given attempt number (1-indexed).
    def compute_delay(attempt)
      base = parse_duration(@initial_interval)
      max = parse_duration(@max_interval)

      delay = base * (@backoff_coefficient**(attempt - 1))
      delay = [delay, max].min

      if @jitter
        jitter_factor = rand(0.5..1.5)
        delay = delay * jitter_factor
        delay = [delay, max].min
      end

      delay
    end

    # Check if an error type should skip retries.
    def non_retryable?(error_type)
      @non_retryable_errors.any? do |pattern|
        if pattern.end_with?(".*")
          prefix = pattern[0..-3]
          error_type == prefix || error_type.start_with?("#{prefix}.")
        else
          error_type == pattern
        end
      end
    end

    # Parse ISO 8601 duration to seconds.
    def self.parse_duration(str)
      return 0 if str.nil? || str.empty?

      match = str.match(/\APT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?\z/)
      if match
        hours = (match[1] || 0).to_f
        minutes = (match[2] || 0).to_f
        seconds = (match[3] || 0).to_f
        return hours * 3600 + minutes * 60 + seconds
      end

      match = str.match(/\AP(?:(\d+)D)?T?(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?\z/)
      if match
        days = (match[1] || 0).to_f
        hours = (match[2] || 0).to_f
        minutes = (match[3] || 0).to_f
        seconds = (match[4] || 0).to_f
        return days * 86_400 + hours * 3600 + minutes * 60 + seconds
      end

      raise ArgumentError, "Invalid ISO 8601 duration: #{str}"
    end

    private

    def parse_duration(str)
      self.class.parse_duration(str)
    end

    def validate!
      raise ArgumentError, "max_attempts must be >= 1" if @max_attempts < 1
      raise ArgumentError, "backoff_coefficient must be >= 1.0" if @backoff_coefficient < 1.0
      unless %w[discard dead_letter].include?(@on_exhaustion)
        raise ArgumentError, "on_exhaustion must be 'discard' or 'dead_letter'"
      end
    end
  end
end
