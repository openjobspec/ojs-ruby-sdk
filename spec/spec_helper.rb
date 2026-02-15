# frozen_string_literal: true

if ENV.fetch("COVERAGE", nil)
  require "simplecov"
  SimpleCov.start do
    add_filter "/spec/"
    add_filter "/vendor/"
    enable_coverage :branch
    minimum_coverage 80
  end
end

require "logger"
require "webmock/rspec"
require_relative "../lib/ojs"

# Test constants — accessible directly in specs
OJS_TEST_BASE_URL    = "http://localhost:8080"
OJS_TEST_API_BASE    = "#{OJS_TEST_BASE_URL}/ojs/v1"
OJS_TEST_CONTENT_TYPE = "application/openjobspec+json"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end

# Shared test helpers
module OJSTestHelpers
  def base_url
    OJS_TEST_BASE_URL
  end

  def api_base
    OJS_TEST_API_BASE
  end

  def stub_ojs_post(path, request_body: nil, response_body: {}, status: 200)
    stub = stub_request(:post, "#{api_base}#{path}")
      .with(headers: { "Content-Type" => OJS_TEST_CONTENT_TYPE })
    stub = stub.with(body: request_body) if request_body
    stub.to_return(
      status: status,
      body: response_body.to_json,
      headers: { "Content-Type" => OJS_TEST_CONTENT_TYPE }
    )
  end

  def stub_ojs_get(path, response_body: {}, status: 200)
    stub_request(:get, "#{api_base}#{path}")
      .with(headers: { "Accept" => OJS_TEST_CONTENT_TYPE })
      .to_return(
        status: status,
        body: response_body.to_json,
        headers: { "Content-Type" => OJS_TEST_CONTENT_TYPE }
      )
  end

  def stub_ojs_delete(path, response_body: {}, status: 200)
    stub_request(:delete, "#{api_base}#{path}")
      .to_return(
        status: status,
        body: response_body.to_json,
        headers: { "Content-Type" => OJS_TEST_CONTENT_TYPE }
      )
  end

  def sample_job_response(overrides = {})
    {
      "specversion" => OJS::SPEC_VERSION,
      "id" => "019461a8-1a2b-7c3d-8e4f-5a6b7c8d9e0f",
      "type" => "email.send",
      "queue" => "default",
      "args" => [{ "to" => "user@example.com" }],
      "state" => "available",
      "attempt" => 0,
      "created_at" => "2026-01-01T00:00:00Z",
    }.merge(overrides)
  end
end

RSpec.configure do |config|
  config.include OJSTestHelpers
end
