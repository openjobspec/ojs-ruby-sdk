# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "securerandom"
require "time"

module OJS
  # Durable job handler with checkpoint-based crash recovery.
  #
  # Subclass this and use {#save_checkpoint} / {#resume_checkpoint} to persist
  # intermediate state. If the worker crashes, the job resumes from the last
  # checkpoint instead of restarting.
  #
  # @example
  #   class DataMigration < OJS::DurableWorker
  #     def perform(ctx)
  #       progress = resume_checkpoint(ctx) || { "processed" => 0 }
  #       records.each_with_index do |record, i|
  #         next if i < progress["processed"]
  #         process(record)
  #         save_checkpoint(ctx, { "processed" => i + 1 }) if (i % 1000).zero?
  #       end
  #     end
  #   end
  class DurableWorker
    # Save a checkpoint for the current job.
    #
    # @param ctx [JobContext] the job context
    # @param state [Hash, Array, String, Numeric] JSON-serializable state
    def save_checkpoint(ctx, state)
      uri = URI("#{ctx.server_url}/ojs/v1/jobs/#{ctx.job.id}/checkpoint")
      req = Net::HTTP::Put.new(uri, "Content-Type" => "application/json")
      req.body = JSON.generate({ state: state })
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(req)
      end
    end

    # Resume from the last checkpoint, if one exists.
    #
    # @param ctx [JobContext] the job context
    # @return [Object, nil] the deserialized checkpoint state, or nil
    def resume_checkpoint(ctx)
      uri = URI("#{ctx.server_url}/ojs/v1/jobs/#{ctx.job.id}/checkpoint")
      resp = Net::HTTP.get_response(uri)
      return nil unless resp.is_a?(Net::HTTPSuccess)

      data = JSON.parse(resp.body)
      data["state"]
    rescue StandardError
      nil
    end

    # Delete a checkpoint for the current job.
    # Idempotent: returns true even if no checkpoint exists (404).
    #
    # @param ctx [JobContext] the job context
    # @return [Boolean] true on success, false on error
    def delete_checkpoint(ctx)
      uri = URI("#{ctx.server_url}/ojs/v1/jobs/#{ctx.job.id}/checkpoint")
      req = Net::HTTP::Delete.new(uri, "Content-Type" => "application/json")
      resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(req)
      end
      resp.is_a?(Net::HTTPSuccess) || resp.code == "404"
    rescue StandardError
      false
    end
  end

  # Deterministic execution context for durable workflows.
  #
  # Wraps a {JobContext} and provides helpers that record their results on the
  # first execution and replay them on retry, ensuring deterministic behavior
  # across crashes and restarts. Non-deterministic operations (timestamps,
  # random values, external calls) are captured in a replay log so that
  # re-execution produces identical results.
  #
  # @example
  #   class PaymentJob < OJS::DurableWorker
  #     def perform(ctx)
  #       dc = OJS::DurableContext.new(ctx)
  #       timestamp = dc.now
  #       idempotency_key = dc.random(16)
  #       result = dc.side_effect("charge") { stripe_charge(amount, idempotency_key) }
  #       dc.save({ "charged" => true, "result" => result })
  #       dc.complete
  #     end
  #   end
  class DurableContext
    # @return [Array<Hash>] the replay log entries with seq, type, key, result
    attr_reader :replay_log

    # @return [JobContext] the underlying job context
    attr_reader :ctx

    # Initialize a durable context for the given job.
    # Loads the replay log from the checkpoint resume endpoint.
    #
    # @param ctx [JobContext] the job context
    def initialize(ctx)
      @ctx = ctx
      @seq = 0
      @worker = DurableWorker.new
      @replay_log = load_replay_log
    end

    # Return a deterministic timestamp.
    # Records Time.now on first call; replays the recorded value on retry.
    #
    # @return [Time] the deterministic timestamp
    def now
      entry = find_replay_entry(@seq, "now")
      if entry
        @seq += 1
        Time.parse(entry["result"])
      else
        t = Time.now.utc
        record_entry("now", "now", t.iso8601(6))
        @seq += 1
        t
      end
    end

    # Return a deterministic random hex string.
    # Records SecureRandom.hex on first call; replays the recorded value on retry.
    #
    # @param num_bytes [Integer] number of random bytes (hex output is 2x this length)
    # @return [String] hex-encoded random string
    def random(num_bytes)
      entry = find_replay_entry(@seq, "random")
      if entry
        @seq += 1
        entry["result"]
      else
        hex = SecureRandom.hex(num_bytes)
        record_entry("random", "random", hex)
        @seq += 1
        hex
      end
    end

    # Execute a block with deterministic replay.
    # On the first call the block is executed and its result is recorded.
    # On retry the recorded result is returned without re-executing the block.
    # Results are JSON-serialized for storage.
    #
    # @param key [String] unique key identifying this side effect
    # @yield the block to execute on first run
    # @return [Object] the JSON-deserialized result
    def side_effect(key, &block)
      raise ArgumentError, "block required for side_effect" unless block

      entry = find_replay_entry(@seq, "side_effect", key)
      if entry
        @seq += 1
        JSON.parse(entry["result"])
      else
        result = block.call
        record_entry("side_effect", key, JSON.generate(result))
        @seq += 1
        result
      end
    end

    # Save checkpoint state along with the current replay log.
    #
    # @param state [Hash, Array, String, Numeric] JSON-serializable state
    def save(state)
      @worker.save_checkpoint(@ctx, {
        "state" => state,
        "replay_log" => @replay_log,
      })
    end

    # Resume from the last checkpoint.
    #
    # @return [Object, nil] the deserialized user state, or nil
    def resume
      data = @worker.resume_checkpoint(@ctx)
      return nil unless data.is_a?(Hash)

      data["state"]
    end

    # Delete the checkpoint for the current job.
    # Call this when the durable workflow completes successfully.
    #
    # @return [Boolean] true on success, false on error
    def complete
      @worker.delete_checkpoint(@ctx)
    end

    private

    # Load the replay log from the existing checkpoint, if any.
    #
    # @return [Array<Hash>] the replay log entries
    def load_replay_log
      data = @worker.resume_checkpoint(@ctx)
      return [] unless data.is_a?(Hash) && data["replay_log"].is_a?(Array)

      data["replay_log"]
    end

    # Find a matching replay entry by sequence number and type.
    #
    # @param seq [Integer] the sequence number
    # @param type [String] the entry type
    # @param key [String, nil] optional key for side_effect entries
    # @return [Hash, nil] the matching entry or nil
    def find_replay_entry(seq, type, key = nil)
      @replay_log.find do |entry|
        entry["seq"] == seq && entry["type"] == type &&
          (key.nil? || entry["key"] == key)
      end
    end

    # Record a new entry in the replay log.
    #
    # @param type [String] entry type ("now", "random", "side_effect")
    # @param key [String] entry key
    # @param result [String] serialized result value
    def record_entry(type, key, result)
      @replay_log << { "seq" => @seq, "type" => type, "key" => key, "result" => result }
    end
  end
end
