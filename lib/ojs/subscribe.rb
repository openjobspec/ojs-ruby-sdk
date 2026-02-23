# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module OJS
  # Server-Sent Events (SSE) subscription for real-time OJS job events.
  #
  # @example Subscribe to queue events
  #   sub = OJS::SSESubscription.subscribe_queue("http://localhost:8080", "default") do |event|
  #     puts "#{event.type}: #{event.data}"
  #   end
  #   sub.cancel  # stop receiving events
  #
  class SSESubscription
    # An SSE event from the OJS server.
    Event = Struct.new(:id, :type, :data, keyword_init: true)

    attr_reader :cancelled

    def initialize
      @cancelled = false
      @thread = nil
    end

    # Stop receiving events and close the connection.
    def cancel
      @cancelled = true
      @thread&.kill
    end

    # Subscribe to an SSE event stream.
    #
    # @param url [String] Base URL of the OJS server.
    # @param channel [String] SSE channel (e.g., "job:<id>", "queue:<name>").
    # @param auth [String, nil] Bearer auth token.
    # @yield [Event] Called for each received event.
    # @return [SSESubscription]
    def self.subscribe(url, channel, auth: nil, &block)
      sub = new
      stream_url = URI("#{url.chomp('/')}/ojs/v1/events/stream?channel=#{URI.encode_www_form_component(channel)}")

      sub.instance_variable_set(:@thread, Thread.new do
        begin
          Net::HTTP.start(stream_url.host, stream_url.port, use_ssl: stream_url.scheme == "https") do |http|
            request = Net::HTTP::Get.new(stream_url)
            request["Accept"] = "text/event-stream"
            request["Cache-Control"] = "no-cache"
            request["Authorization"] = "Bearer #{auth}" if auth

            http.request(request) do |response|
              event_type = ""
              event_id = ""
              event_data = ""

              response.read_body do |chunk|
                break if sub.cancelled

                chunk.each_line do |line|
                  line = line.chomp

                  if line.empty?
                    unless event_data.empty?
                      parsed = begin
                        JSON.parse(event_data)
                      rescue JSON::ParserError
                        { "raw" => event_data }
                      end

                      block.call(Event.new(
                        id: event_id,
                        type: event_type.empty? ? "message" : event_type,
                        data: parsed
                      ))
                    end
                    event_type = ""
                    event_id = ""
                    event_data = ""
                  elsif line.start_with?("event: ")
                    event_type = line[7..]
                  elsif line.start_with?("id: ")
                    event_id = line[4..]
                  elsif line.start_with?("data: ")
                    event_data = line[6..]
                  end
                end
              end
            end
          end
        rescue IOError, Errno::ECONNRESET => e
          # Expected on cancel
        end
      end)

      sub
    end

    # Subscribe to events for a specific job.
    def self.subscribe_job(url, job_id, auth: nil, &block)
      subscribe(url, "job:#{job_id}", auth: auth, &block)
    end

    # Subscribe to events for all jobs in a queue.
    def self.subscribe_queue(url, queue, auth: nil, &block)
      subscribe(url, "queue:#{queue}", auth: auth, &block)
    end
  end
end
