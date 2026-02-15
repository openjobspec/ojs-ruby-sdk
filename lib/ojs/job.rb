# frozen_string_literal: true

require "securerandom"

module OJS
  # Value object representing an OJS job envelope.
  class Job
    # Required attributes
    attr_reader :id, :type, :queue

    # Args — exposed as Hash (common case) or Array
    attr_reader :args

    # Optional attributes
    attr_reader :meta, :priority, :timeout, :scheduled_at, :expires_at,
                :retry_policy, :unique_policy, :schema

    # System-managed attributes
    attr_reader :state, :attempt, :created_at, :enqueued_at,
                :started_at, :completed_at, :error, :result

    def initialize( # rubocop:disable Metrics/ParameterLists
      type:, args: {}, id: nil, queue: "default", meta: nil, priority: nil,
      timeout: nil, scheduled_at: nil, expires_at: nil, retry_policy: nil,
      unique_policy: nil, schema: nil, state: nil, attempt: nil,
      created_at: nil, enqueued_at: nil, started_at: nil, completed_at: nil,
      error: nil, result: nil
    )
      @id = id || self.class.generate_id
      @type = type
      @queue = queue
      @args = args
      @meta = meta || {}
      @priority = priority
      @timeout = timeout
      @scheduled_at = scheduled_at
      @expires_at = expires_at
      @retry_policy = retry_policy
      @unique_policy = unique_policy
      @schema = schema
      @state = state
      @attempt = attempt
      @created_at = created_at
      @enqueued_at = enqueued_at
      @started_at = started_at
      @completed_at = completed_at
      @error = error
      @result = result
    end

    # Build a Job from a wire-format Hash (parsed JSON).
    def self.from_hash(hash)
      hash = normalize_keys(hash)

      args = unwrap_args(hash["args"])
      retry_policy = hash["retry"] ? RetryPolicy.from_hash(hash["retry"]) : nil
      unique_policy = hash["unique"] ? UniquePolicy.from_hash(hash["unique"]) : nil

      new(
        id: hash["id"],
        type: hash["type"],
        queue: hash["queue"] || "default",
        args: args,
        meta: hash["meta"],
        priority: hash["priority"],
        timeout: hash["timeout"],
        scheduled_at: hash["scheduled_at"],
        expires_at: hash["expires_at"],
        retry_policy: retry_policy,
        unique_policy: unique_policy,
        schema: hash["schema"],
        state: hash["state"],
        attempt: hash["attempt"],
        created_at: hash["created_at"],
        enqueued_at: hash["enqueued_at"],
        started_at: hash["started_at"],
        completed_at: hash["completed_at"],
        error: hash["error"],
        result: hash["result"],
      )
    end

    # Serialize to wire-format Hash for JSON encoding.
    def to_hash
      h = {
        "specversion" => SPEC_VERSION,
        "id" => @id,
        "type" => @type,
        "queue" => @queue,
        "args" => wrap_args(@args),
      }
      h["meta"] = @meta unless @meta.nil? || @meta.empty?
      h["priority"] = @priority unless @priority.nil?
      h["timeout"] = @timeout unless @timeout.nil?
      h["scheduled_at"] = @scheduled_at unless @scheduled_at.nil?
      h["expires_at"] = @expires_at unless @expires_at.nil?
      h["retry"] = @retry_policy.to_hash if @retry_policy
      h["unique"] = @unique_policy.to_hash if @unique_policy
      h["schema"] = @schema unless @schema.nil?
      h
    end

    def inspect
      "#<OJS::Job id=#{@id} type=#{@type.inspect} queue=#{@queue.inspect} state=#{@state.inspect}>"
    end

    def ==(other)
      other.is_a?(Job) && id == other.id
    end
    alias_method :eql?, :==

    def hash
      [self.class, @id].hash
    end

    # Generate a UUIDv7 string.
    def self.generate_id
      # UUIDv7: 48-bit timestamp (ms) + 4-bit version(7) + 12-bit random + 2-bit variant(10) + 62-bit random
      now_ms = (Time.now.to_f * 1000).to_i
      random_bytes = SecureRandom.random_bytes(10)

      # Bytes 0-5: timestamp
      ts_bytes = [now_ms].pack("Q>")[2, 6] # 48 bits

      # Byte 6: version (0111) + 4 bits random
      b6 = (0x70 | (random_bytes.getbyte(0) & 0x0F))

      # Byte 7: random
      b7 = random_bytes.getbyte(1)

      # Byte 8: variant (10) + 6 bits random
      b8 = (0x80 | (random_bytes.getbyte(2) & 0x3F))

      # Bytes 9-15: random
      uuid_bytes = ts_bytes + [b6, b7, b8].pack("CCC") + random_bytes[3, 7]

      hex = uuid_bytes.unpack1("H*")
      "#{hex[0, 8]}-#{hex[8, 4]}-#{hex[12, 4]}-#{hex[16, 4]}-#{hex[20, 12]}"
    end

    private

    # Wrap args for wire format: Hash → [Hash], Array stays as-is.
    def wrap_args(args)
      case args
      when Hash then [stringify_keys(args)]
      when Array then args
      else [args]
      end
    end

    # Unwrap args from wire format: [single_hash] → Hash, otherwise Array.
    def self.unwrap_args(wire_args)
      return {} if wire_args.nil? || (wire_args.is_a?(Array) && wire_args.empty?)

      if wire_args.is_a?(Array) && wire_args.length == 1 && wire_args[0].is_a?(Hash)
        wire_args[0]
      else
        wire_args
      end
    end

    def self.normalize_keys(hash)
      return hash unless hash.is_a?(Hash)

      hash.transform_keys(&:to_s)
    end

    def stringify_keys(hash)
      return hash unless hash.is_a?(Hash)

      hash.transform_keys(&:to_s)
    end
  end
end
