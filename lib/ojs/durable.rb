# frozen_string_literal: true

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
  end
end
