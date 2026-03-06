# frozen_string_literal: true

require_relative "spec_helper"
require_relative "../lib/ojs/error_codes"

RSpec.describe OJS::ErrorCodes do
  describe "ErrorCodeEntry" do
    it "stores all attributes" do
      entry = OJS::ErrorCodes::ErrorCodeEntry.new(
        code: "OJS-9999",
        name: "TestError",
        canonical_code: "TEST_ERROR",
        http_status: 418,
        message: "I'm a teapot",
        retryable: true
      )

      expect(entry.code).to eq("OJS-9999")
      expect(entry.name).to eq("TestError")
      expect(entry.canonical_code).to eq("TEST_ERROR")
      expect(entry.http_status).to eq(418)
      expect(entry.message).to eq("I'm a teapot")
      expect(entry.retryable).to be true
    end

    it "formats to_s with code, name, and message" do
      entry = OJS::ErrorCodes::INVALID_PAYLOAD

      expect(entry.to_s).to eq("[OJS-1000] InvalidPayload: Job envelope fails structural validation")
    end
  end

  describe "ALL" do
    it "contains exactly 54 error codes" do
      expect(OJS::ErrorCodes::ALL.size).to eq(54)
    end

    it "is frozen" do
      expect(OJS::ErrorCodes::ALL).to be_frozen
    end

    it "has all unique OJS-XXXX codes" do
      codes = OJS::ErrorCodes::ALL.map(&:code)
      expect(codes.uniq.size).to eq(codes.size)
    end

    it "has all unique names" do
      names = OJS::ErrorCodes::ALL.map(&:name)
      expect(names.uniq.size).to eq(names.size)
    end

    it "has all codes matching OJS-XXXX format" do
      OJS::ErrorCodes::ALL.each do |entry|
        expect(entry.code).to match(/\AOJS-\d{4}\z/), "#{entry.name} has invalid code: #{entry.code}"
      end
    end
  end

  describe "category counts" do
    it "has 18 client errors (OJS-1xxx)" do
      count = OJS::ErrorCodes::ALL.count { |e| e.code.start_with?("OJS-1") }
      expect(count).to eq(18)
    end

    it "has 5 server errors (OJS-2xxx)" do
      count = OJS::ErrorCodes::ALL.count { |e| e.code.start_with?("OJS-2") }
      expect(count).to eq(5)
    end

    it "has 11 lifecycle errors (OJS-3xxx)" do
      count = OJS::ErrorCodes::ALL.count { |e| e.code.start_with?("OJS-3") }
      expect(count).to eq(11)
    end

    it "has 7 workflow errors (OJS-4xxx)" do
      count = OJS::ErrorCodes::ALL.count { |e| e.code.start_with?("OJS-4") }
      expect(count).to eq(7)
    end

    it "has 4 auth errors (OJS-5xxx)" do
      count = OJS::ErrorCodes::ALL.count { |e| e.code.start_with?("OJS-5") }
      expect(count).to eq(4)
    end

    it "has 4 rate limiting errors (OJS-6xxx)" do
      count = OJS::ErrorCodes::ALL.count { |e| e.code.start_with?("OJS-6") }
      expect(count).to eq(4)
    end

    it "has 5 extension errors (OJS-7xxx)" do
      count = OJS::ErrorCodes::ALL.count { |e| e.code.start_with?("OJS-7") }
      expect(count).to eq(5)
    end
  end

  describe ".lookup_by_code" do
    it "returns the entry for a valid OJS code" do
      entry = described_class.lookup_by_code("OJS-1000")

      expect(entry).to eq(OJS::ErrorCodes::INVALID_PAYLOAD)
      expect(entry.name).to eq("InvalidPayload")
    end

    it "returns nil for an unknown code" do
      expect(described_class.lookup_by_code("OJS-9999")).to be_nil
    end

    it "finds every entry in ALL by code" do
      OJS::ErrorCodes::ALL.each do |entry|
        expect(described_class.lookup_by_code(entry.code)).to eq(entry)
      end
    end
  end

  describe ".lookup_by_canonical_code" do
    it "returns the entry for a valid canonical code" do
      entry = described_class.lookup_by_canonical_code("INVALID_PAYLOAD")

      expect(entry).to eq(OJS::ErrorCodes::INVALID_PAYLOAD)
      expect(entry.code).to eq("OJS-1000")
    end

    it "returns nil for an unknown canonical code" do
      expect(described_class.lookup_by_canonical_code("DOES_NOT_EXIST")).to be_nil
    end

    it "returns nil for empty-string canonical codes" do
      expect(described_class.lookup_by_canonical_code("")).to be_nil
    end

    it "finds every entry with a non-empty canonical code" do
      entries_with_canonical = OJS::ErrorCodes::ALL.reject { |e| e.canonical_code.empty? }
      expect(entries_with_canonical).not_to be_empty

      entries_with_canonical.each do |entry|
        expect(described_class.lookup_by_canonical_code(entry.canonical_code)).to eq(entry)
      end
    end
  end

  describe "specific constants" do
    it "defines INVALID_PAYLOAD correctly" do
      e = OJS::ErrorCodes::INVALID_PAYLOAD
      expect(e.code).to eq("OJS-1000")
      expect(e.canonical_code).to eq("INVALID_PAYLOAD")
      expect(e.http_status).to eq(400)
      expect(e.retryable).to be false
    end

    it "defines CONNECTION_ERROR as retryable with no canonical code" do
      e = OJS::ErrorCodes::CONNECTION_ERROR
      expect(e.code).to eq("OJS-1011")
      expect(e.canonical_code).to eq("")
      expect(e.http_status).to eq(0)
      expect(e.retryable).to be true
    end

    it "defines BACKEND_UNAVAILABLE as retryable" do
      e = OJS::ErrorCodes::BACKEND_UNAVAILABLE
      expect(e.code).to eq("OJS-2001")
      expect(e.retryable).to be true
      expect(e.http_status).to eq(503)
    end

    it "defines JOB_NOT_FOUND with NOT_FOUND canonical code" do
      e = OJS::ErrorCodes::JOB_NOT_FOUND
      expect(e.code).to eq("OJS-3000")
      expect(e.canonical_code).to eq("NOT_FOUND")
      expect(e.http_status).to eq(404)
      expect(e.retryable).to be false
    end

    it "defines RATE_LIMITED as retryable with 429 status" do
      e = OJS::ErrorCodes::RATE_LIMITED
      expect(e.code).to eq("OJS-6000")
      expect(e.http_status).to eq(429)
      expect(e.retryable).to be true
    end
  end
end
