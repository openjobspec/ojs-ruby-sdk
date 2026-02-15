# frozen_string_literal: true

require_relative "lib/ojs/version"

Gem::Specification.new do |spec|
  spec.name          = "ojs"
  spec.version       = OJS::VERSION
  spec.authors       = ["OJS Contributors"]
  spec.email         = ["ojs@example.com"]

  spec.summary       = "Official Ruby SDK for the Open Job Spec (OJS) protocol"
  spec.description   = "A zero-dependency Ruby client and worker for enqueuing, consuming, and " \
                        "orchestrating background jobs via the Open Job Spec (OJS) protocol. " \
                        "Supports retry policies, unique jobs, workflows (chain/group/batch), " \
                        "and Rack-style middleware."
  spec.homepage      = "https://github.com/openjobspec/ojs-ruby-sdk"
  spec.license       = "Apache-2.0"

  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata = {
    "homepage_uri"      => spec.homepage,
    "source_code_uri"   => spec.homepage,
    "changelog_uri"     => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "bug_tracker_uri"   => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true",
  }

  spec.files = Dir.glob("lib/**/*.rb") + %w[README.md LICENSE CHANGELOG.md]
  spec.require_paths = ["lib"]

  # Zero runtime dependencies — only net/http, json, uri, securerandom from stdlib.

  # Development dependencies
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "webmock", "~> 3.14.0"
end
