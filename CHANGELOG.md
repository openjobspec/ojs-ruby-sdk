# Changelog

## [0.2.0](https://github.com/openjobspec/ojs-ruby-sdk/compare/v0.1.0...v0.2.0) (2026-02-28)


### Features

* add connection pool support for multi-threaded workers ([1cb08e2](https://github.com/openjobspec/ojs-ruby-sdk/commit/1cb08e213af05f1ccf7239a7080ed4bf0414f596))
* implement configurable retry backoff ([ecfccfd](https://github.com/openjobspec/ojs-ruby-sdk/commit/ecfccfd20042788c18aedf6600b819d0f75a223f))


### Bug Fixes

* correct error handling in graceful shutdown ([07b1212](https://github.com/openjobspec/ojs-ruby-sdk/commit/07b12126d705cbd3a5bd5e350305c1cf9f62e9a3))
* correct signal handling in worker process ([2930c83](https://github.com/openjobspec/ojs-ruby-sdk/commit/2930c83484d1296b27296488ad5c84fab75de575))
* handle connection timeout in HTTP client ([750afd2](https://github.com/openjobspec/ojs-ruby-sdk/commit/750afd2ac7f5e7b0f75ac74d3425efdf34afa848))


### Performance Improvements

* reduce memory allocations in hot path ([bf04c81](https://github.com/openjobspec/ojs-ruby-sdk/commit/bf04c8120cc29e7f353f74e359cde802877c7de3))

## 0.1.0 (Unreleased)

### Features
- OJS spec version 1.0.0-rc.1 support
- Client: enqueue, enqueue_batch, workflow, get_job, cancel_job
- Worker: register handlers, middleware chain, thread pool, heartbeat
- Queue operations: list, stats, pause, resume
- Dead letter operations: list, retry, discard
- Retry policies with exponential backoff and jitter
- Unique job deduplication policies
- Workflows: chain, group, batch with callbacks
- Rack-style yield-based middleware
- Zero runtime dependencies (net/http, json from stdlib)
- Pluggable logger for Worker (defaults to Logger on $stdout)
- User-Agent header sent with all HTTP requests
- `Client#close` for connection cleanup
- `Event#to_hash` for serialization round-trip consistency
- `QueueStats#to_hash` for serialization round-trip consistency
- Equality methods (`==`, `eql?`, `hash`) on Job, RetryPolicy, UniquePolicy
- `OJS::Testing::FakeTransport` for intercepting Client calls in test mode
- Pluggable transport on `Client.new` via `transport:` parameter
- Client-side input validation: type, ID, and queue name sanitization
- URL-encoding of IDs and names in URL paths to prevent injection

### Improvements
- Persistent HTTP connections with keep-alive (thread-safe via thread-local storage)
- Fixed race condition in Worker state checks (TOCTOU on @active_jobs)
- Fixed worker busy-wait: blocking Queue#pop replaces non-blocking pop + sleep
- Fixed signal handler deadlock risk (mutex acquisition in trap context)
- Fixed silent JSON parse errors on success responses (now raises OJS::Error)
- Fixed ValidationError constructor kwargs mutation
- Fixed bare rescue in Worker#process_job (now rescues StandardError only)
- Fixed transport retry: stale connections are now retried once before raising
- Fixed dead code in WorkflowDefinition#step_to_hash
- Fixed Worker fetch_jobs over-fetching by accounting for active jobs count
- Consolidated duration parsing: `RetryPolicy.parse_duration` now supports human-friendly shorthand ("30s", "5m", "2h", "1d")
- Added `#inspect` methods to Job, RetryPolicy, UniquePolicy, QueueStats
- Added `#close` method to Transport::HTTP for connection cleanup
- Stale connection detection with automatic reset on IOError/EOFError

### Testing
- Added unit tests for Job (serialization, deserialization, UUIDv7)
- Added unit tests for Transport::HTTP (all HTTP methods, error handling)
- Added unit tests for Error hierarchy (all error classes, from_response)
- Added unit tests for QueueStats (construction, from_hash)
- Added unit tests for UniquePolicy (validation, serialization)
- Added unit tests for Event and Events constants

### Project
- Added GitHub Actions CI with Ruby 3.2/3.3/3.4 matrix
- Added RuboCop and rubocop-rspec linting to CI
- Added SimpleCov code coverage (opt-in via COVERAGE=1)
- Added bundler-audit security scanning to CI
- Added GitHub Actions release workflow for RubyGems publishing
- Added Dependabot configuration for bundler and GitHub Actions
- Added CONTRIBUTING.md
- Added CODE_OF_CONDUCT.md
- Added issue templates (bug report, feature request)
- Added pull request template
- Added README badges (CI, gem version, Ruby version, license)
- Fixed license inconsistency (README now matches Apache-2.0 in gemspec/LICENSE)
