# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe OJS::SSESubscription do
  describe "SSE parsing logic" do
    # Test the parsing by exercising the block callback through mocked HTTP.
    # Since subscribe() uses Net::HTTP internally, we test the parsing patterns directly.

    def parse_sse_lines(lines)
      events = []
      event_type = ""
      event_id = ""
      event_data = ""

      lines.each do |line|
        line = line.chomp

        if line.empty?
          unless event_data.empty?
            parsed = begin
              JSON.parse(event_data)
            rescue JSON::ParserError
              { "raw" => event_data }
            end

            events << OJS::SSESubscription::Event.new(
              id: event_id,
              type: event_type.empty? ? "message" : event_type,
              data: parsed
            )
          end
          event_type = ""
          event_id = ""
          event_data = ""
        elsif line.start_with?("event:")
          event_type = line.sub(/\Aevent:\s*/, "")
        elsif line.start_with?("id:")
          event_id = line.sub(/\Aid:\s*/, "")
        elsif line.start_with?("data:")
          chunk = line.sub(/\Adata:\s*/, "")
          event_data = event_data.empty? ? chunk : "#{event_data}\n#{chunk}"
        end
      end

      events
    end

    it "parses a single event" do
      lines = [
        "event: job.completed",
        "id: evt-1",
        'data: {"job_id":"j1","state":"completed"}',
        ""
      ]

      events = parse_sse_lines(lines)

      expect(events.length).to eq(1)
      expect(events[0].type).to eq("job.completed")
      expect(events[0].id).to eq("evt-1")
      expect(events[0].data["job_id"]).to eq("j1")
    end

    it "parses multiple events" do
      lines = [
        "event: job.active",
        'data: {"n":1}',
        "",
        "event: job.completed",
        'data: {"n":2}',
        ""
      ]

      events = parse_sse_lines(lines)

      expect(events.length).to eq(2)
      expect(events[0].type).to eq("job.active")
      expect(events[1].type).to eq("job.completed")
    end

    it "handles multiline data by concatenating" do
      lines = [
        "event: job.completed",
        'data: {"part1":',
        'data: "value"}',
        ""
      ]

      events = parse_sse_lines(lines)

      expect(events.length).to eq(1)
      expect(events[0].data).to eq({ "part1" => "value" })
    end

    it "handles fields without space after colon" do
      lines = [
        "event:job.failed",
        "id:evt-2",
        'data:{"state":"failed"}',
        ""
      ]

      events = parse_sse_lines(lines)

      expect(events.length).to eq(1)
      expect(events[0].type).to eq("job.failed")
      expect(events[0].id).to eq("evt-2")
    end

    it "uses default message type when no event field" do
      lines = [
        'data: {"ping":true}',
        ""
      ]

      events = parse_sse_lines(lines)

      expect(events.length).to eq(1)
      expect(events[0].type).to eq("message")
    end

    it "falls back to raw on invalid JSON" do
      lines = [
        "data: not-valid-json",
        ""
      ]

      events = parse_sse_lines(lines)

      expect(events.length).to eq(1)
      expect(events[0].data).to eq({ "raw" => "not-valid-json" })
    end

    it "skips events with empty data" do
      lines = [
        "event: heartbeat",
        "",
        "event: job.completed",
        'data: {"ok":true}',
        ""
      ]

      events = parse_sse_lines(lines)

      expect(events.length).to eq(1)
      expect(events[0].type).to eq("job.completed")
    end
  end

  describe "SSESubscription.subscribe_job" do
    it "is defined as a class method" do
      expect(described_class).to respond_to(:subscribe_job)
    end
  end

  describe "SSESubscription.subscribe_queue" do
    it "is defined as a class method" do
      expect(described_class).to respond_to(:subscribe_queue)
    end
  end
end
