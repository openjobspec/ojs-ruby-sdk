# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe OJS::MiddlewareChain do
  let(:chain) { described_class.new }

  describe "#add / #use" do
    it "adds middleware to the chain" do
      chain.add("test") { |ctx, &nxt| nxt.call }

      expect(chain.size).to eq(1)
    end

    it "raises without a block" do
      expect { chain.add("test") }.to raise_error(ArgumentError)
    end
  end

  describe "#prepend" do
    it "adds middleware to the beginning" do
      chain.add("second") { |ctx, &nxt| nxt.call }
      chain.prepend("first") { |ctx, &nxt| nxt.call }

      names = chain.entries.map(&:first)
      expect(names).to eq(["first", "second"])
    end
  end

  describe "#insert_before" do
    it "inserts before a named middleware" do
      chain.add("first") { |ctx, &nxt| nxt.call }
      chain.add("third") { |ctx, &nxt| nxt.call }
      chain.insert_before("third", "second") { |ctx, &nxt| nxt.call }

      names = chain.entries.map(&:first)
      expect(names).to eq(["first", "second", "third"])
    end

    it "raises when target not found" do
      expect {
        chain.insert_before("missing", "new") { |ctx, &nxt| nxt.call }
      }.to raise_error(ArgumentError, /not found/)
    end
  end

  describe "#insert_after" do
    it "inserts after a named middleware" do
      chain.add("first") { |ctx, &nxt| nxt.call }
      chain.add("third") { |ctx, &nxt| nxt.call }
      chain.insert_after("first", "second") { |ctx, &nxt| nxt.call }

      names = chain.entries.map(&:first)
      expect(names).to eq(["first", "second", "third"])
    end
  end

  describe "#remove" do
    it "removes a named middleware" do
      chain.add("keep") { |ctx, &nxt| nxt.call }
      chain.add("remove_me") { |ctx, &nxt| nxt.call }
      chain.remove("remove_me")

      expect(chain.size).to eq(1)
      expect(chain.include?("remove_me")).to be false
    end
  end

  describe "#include?" do
    it "checks for named middleware" do
      chain.add("exists") { |ctx, &nxt| nxt.call }

      expect(chain.include?("exists")).to be true
      expect(chain.include?("missing")).to be false
    end
  end

  describe "#invoke" do
    it "executes middleware in order around a terminal handler" do
      order = []

      chain.add("first") do |ctx, &nxt|
        order << :first_before
        result = nxt.call
        order << :first_after
        result
      end

      chain.add("second") do |ctx, &nxt|
        order << :second_before
        result = nxt.call
        order << :second_after
        result
      end

      result = chain.invoke(:ctx) do
        order << :terminal
        :done
      end

      expect(order).to eq([:first_before, :second_before, :terminal, :second_after, :first_after])
      expect(result).to eq(:done)
    end

    it "allows middleware to short-circuit the chain" do
      order = []

      chain.add("guard") do |ctx, &nxt|
        order << :guard
        :blocked  # Don't call nxt
      end

      chain.add("never_reached") do |ctx, &nxt|
        order << :never
        nxt.call
      end

      result = chain.invoke(:ctx) { order << :terminal; :done }

      expect(order).to eq([:guard])
      expect(result).to eq(:blocked)
    end

    it "passes context to middleware" do
      received_ctx = nil

      chain.add("capture") do |ctx, &nxt|
        received_ctx = ctx
        nxt.call
      end

      chain.invoke(:my_context) { :done }

      expect(received_ctx).to eq(:my_context)
    end

    it "works with no middleware (just terminal)" do
      result = chain.invoke(:ctx) { :direct }

      expect(result).to eq(:direct)
    end

    it "propagates exceptions through the chain" do
      chain.add("outer") do |ctx, &nxt|
        begin
          nxt.call
        rescue => e
          raise "wrapped: #{e.message}"
        end
      end

      expect {
        chain.invoke(:ctx) { raise "boom" }
      }.to raise_error(RuntimeError, "wrapped: boom")
    end

    it "allows middleware to modify the result" do
      chain.add("transform") do |ctx, &nxt|
        result = nxt.call
        result.upcase
      end

      result = chain.invoke(:ctx) { "hello" }

      expect(result).to eq("HELLO")
    end
  end
end
