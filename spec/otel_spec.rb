# frozen_string_literal: true

require_relative "spec_helper"
require_relative "../lib/ojs/otel"

# Minimal test doubles for OpenTelemetry API without requiring the gem.
# These follow the OpenTelemetry Ruby API contracts.

module FakeOTel
  class Status
    attr_reader :code, :description

    def self.ok
      new(:ok, "")
    end

    def self.error(msg = "")
      new(:error, msg)
    end

    def initialize(code, description)
      @code = code
      @description = description
    end
  end

  class Span
    attr_accessor :status, :name, :attributes
    attr_reader :exceptions

    def initialize(name, attributes: {}, kind: nil)
      @name = name
      @attributes = attributes
      @kind = kind
      @status = nil
      @exceptions = []
    end

    def record_exception(e)
      @exceptions << e
    end
  end

  class Tracer
    attr_reader :spans

    def initialize
      @spans = []
    end

    def in_span(name, attributes: {}, kind: nil)
      span = Span.new(name, attributes: attributes, kind: kind)
      @spans << span
      yield span
    end
  end

  class TracerProvider
    def tracer(name)
      @tracer ||= Tracer.new
    end
  end

  class Counter
    attr_reader :recordings

    def initialize(name, unit: nil, description: nil)
      @name = name
      @recordings = []
    end

    def add(value, attributes: {})
      @recordings << { value: value, attributes: attributes }
    end
  end

  class Histogram
    attr_reader :recordings

    def initialize(name, unit: nil, description: nil)
      @name = name
      @recordings = []
    end

    def record(value, attributes: {})
      @recordings << { value: value, attributes: attributes }
    end
  end

  class Meter
    attr_reader :counters, :histograms

    def initialize
      @counters = {}
      @histograms = {}
    end

    def create_counter(name, unit: nil, description: nil)
      @counters[name] = Counter.new(name, unit: unit, description: description)
    end

    def create_histogram(name, unit: nil, description: nil)
      @histograms[name] = Histogram.new(name, unit: unit, description: description)
    end
  end

  class MeterProvider
    def meter(name)
      @meter ||= Meter.new
    end
  end
end

# Minimal job/context doubles
FakeJob = Struct.new(:id, :type, :queue, :attempt, keyword_init: true) do
  def initialize(id: "job-1", type: "email.send", queue: "default", attempt: 1)
    super
  end
end

FakeContext = Struct.new(:job, keyword_init: true)

RSpec.describe OJS::OpenTelemetryMiddleware do
  describe "without OpenTelemetry" do
    it "executes the handler and returns its result" do
      mw = described_class.new
      ctx = FakeContext.new(job: FakeJob.new)

      result = mw.call(ctx) { "done" }
      expect(result).to eq("done")
    end

    it "propagates exceptions" do
      mw = described_class.new
      ctx = FakeContext.new(job: FakeJob.new)

      expect {
        mw.call(ctx) { raise StandardError, "boom" }
      }.to raise_error(StandardError, "boom")
    end
  end

  describe "with tracer" do
    let(:tracer_provider) { FakeOTel::TracerProvider.new }
    let(:mw) { described_class.new(tracer_provider: tracer_provider) }

    before do
      # Define minimal OpenTelemetry module for tracer resolution
      stub_const("OpenTelemetry", Module.new do
        def self.tracer_provider; end
        def self.respond_to?(name, *args)
          name == :tracer_provider || super
        end
      end)
      stub_const("OpenTelemetry::Trace::Status", FakeOTel::Status)
    end

    it "creates a consumer span with job attributes" do
      ctx = FakeContext.new(job: FakeJob.new(type: "video.transcode", queue: "media"))
      mw.call(ctx) { "ok" }

      tracer = tracer_provider.tracer("ojs-ruby-sdk")
      expect(tracer.spans.size).to eq(1)
      span = tracer.spans.first
      expect(span.name).to eq("process video.transcode")
      expect(span.attributes["ojs.job.type"]).to eq("video.transcode")
      expect(span.attributes["ojs.job.queue"]).to eq("media")
      expect(span.attributes["messaging.system"]).to eq("ojs")
    end

    it "sets span status to ok on success" do
      ctx = FakeContext.new(job: FakeJob.new)
      mw.call(ctx) { "ok" }

      span = tracer_provider.tracer("ojs-ruby-sdk").spans.first
      expect(span.status.code).to eq(:ok)
    end

    it "sets span status to error and records exception on failure" do
      ctx = FakeContext.new(job: FakeJob.new)

      expect {
        mw.call(ctx) { raise StandardError, "oops" }
      }.to raise_error(StandardError, "oops")

      span = tracer_provider.tracer("ojs-ruby-sdk").spans.first
      expect(span.status.code).to eq(:error)
      expect(span.status.description).to eq("oops")
      expect(span.exceptions.size).to eq(1)
      expect(span.exceptions.first.message).to eq("oops")
    end
  end

  describe "with meter provider" do
    let(:meter_provider) { FakeOTel::MeterProvider.new }
    let(:mw) { described_class.new(meter_provider: meter_provider) }

    it "records completed counter and duration on success" do
      ctx = FakeContext.new(job: FakeJob.new(type: "email.send", queue: "email"))
      mw.call(ctx) { "ok" }

      meter = meter_provider.meter("ojs-ruby-sdk")

      completed = meter.counters["ojs.job.completed"]
      expect(completed).not_to be_nil
      expect(completed.recordings.size).to eq(1)
      expect(completed.recordings.first[:value]).to eq(1)
      expect(completed.recordings.first[:attributes]["ojs.job.type"]).to eq("email.send")
      expect(completed.recordings.first[:attributes]["ojs.job.queue"]).to eq("email")

      duration = meter.histograms["ojs.job.duration"]
      expect(duration).not_to be_nil
      expect(duration.recordings.size).to eq(1)
      expect(duration.recordings.first[:value]).to be_a(Float)
      expect(duration.recordings.first[:value]).to be >= 0
    end

    it "records failed counter and duration on failure" do
      ctx = FakeContext.new(job: FakeJob.new(type: "sms.send", queue: "sms"))

      expect {
        mw.call(ctx) { raise StandardError, "fail" }
      }.to raise_error(StandardError)

      meter = meter_provider.meter("ojs-ruby-sdk")

      failed = meter.counters["ojs.job.failed"]
      expect(failed).not_to be_nil
      expect(failed.recordings.size).to eq(1)
      expect(failed.recordings.first[:attributes]["ojs.job.type"]).to eq("sms.send")

      duration = meter.histograms["ojs.job.duration"]
      expect(duration.recordings.size).to eq(1)
    end

    it "records metrics for multiple jobs" do
      mw2 = described_class.new(meter_provider: meter_provider)

      3.times do |i|
        ctx = FakeContext.new(job: FakeJob.new(type: "batch.#{i}", queue: "default"))
        mw2.call(ctx) { "ok" }
      end

      meter = meter_provider.meter("ojs-ruby-sdk")
      completed = meter.counters["ojs.job.completed"]
      expect(completed.recordings.size).to eq(3)

      duration = meter.histograms["ojs.job.duration"]
      expect(duration.recordings.size).to eq(3)
    end
  end

  describe "with both tracer and meter" do
    let(:tracer_provider) { FakeOTel::TracerProvider.new }
    let(:meter_provider) { FakeOTel::MeterProvider.new }
    let(:mw) { described_class.new(tracer_provider: tracer_provider, meter_provider: meter_provider) }

    before do
      stub_const("OpenTelemetry", Module.new do
        def self.tracer_provider; end
        def self.respond_to?(name, *args)
          name == :tracer_provider || super
        end
      end)
      stub_const("OpenTelemetry::Trace::Status", FakeOTel::Status)
    end

    it "creates both spans and metrics" do
      ctx = FakeContext.new(job: FakeJob.new)
      mw.call(ctx) { "ok" }

      tracer = tracer_provider.tracer("ojs-ruby-sdk")
      expect(tracer.spans.size).to eq(1)

      meter = meter_provider.meter("ojs-ruby-sdk")
      expect(meter.counters["ojs.job.completed"].recordings.size).to eq(1)
      expect(meter.histograms["ojs.job.duration"].recordings.size).to eq(1)
    end
  end
end
