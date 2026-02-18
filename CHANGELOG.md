# Changelog

## 1.0.0 (2026-02-18)


### Features

* **client:** add cron job management operations ([fafe442](https://github.com/openjobspec/ojs-ruby-sdk/commit/fafe442dc81e1275ed1d8ba886f73f1df7ef0e64))
* **client:** add input validation and URL path sanitization ([275f1d5](https://github.com/openjobspec/ojs-ruby-sdk/commit/275f1d5d56e1738dfda9b73dc98f94ebbc73424a))
* **client:** add manifest endpoint ([801c3c5](https://github.com/openjobspec/ojs-ruby-sdk/commit/801c3c529e8722d9efe0774168478aca4fe049af))
* **client:** add OJS client with enqueue and queue ops ([89bb0d5](https://github.com/openjobspec/ojs-ruby-sdk/commit/89bb0d58337ece37aaf552478e0cde77e1212c93))
* **client:** add schema registry operations ([7fb9ea6](https://github.com/openjobspec/ojs-ruby-sdk/commit/7fb9ea61eca0882a7e2e9d4e5d2d71ffd36e2002))
* **client:** add transport injection and close method ([f799486](https://github.com/openjobspec/ojs-ruby-sdk/commit/f799486f6cb1aaec6d10adb7665e6c747454c8da))
* **core:** add job, retry, and unique policy value objects ([095876b](https://github.com/openjobspec/ojs-ruby-sdk/commit/095876b634ffc47ce448ae8ac1a95b8f0cc8a2b9))
* **core:** add User-Agent header and inspect methods ([488f79a](https://github.com/openjobspec/ojs-ruby-sdk/commit/488f79a41ac8df11052ee573b304c27780c502cd))
* **core:** add version and error types ([358c237](https://github.com/openjobspec/ojs-ruby-sdk/commit/358c237a8a74432da007a4c67b90efe044dd114f))
* **core:** add workflow builders and middleware chain ([321995a](https://github.com/openjobspec/ojs-ruby-sdk/commit/321995a7a2e073e47038937a882a0911e926162c))
* **errors:** add RateLimitInfo metadata class ([b875cde](https://github.com/openjobspec/ojs-ruby-sdk/commit/b875cde636d37c33e57176553265292753b4b984))
* **middleware:** add logging, timeout, retry, and metrics middleware ([ad763ba](https://github.com/openjobspec/ojs-ruby-sdk/commit/ad763baf2d0c947c78c49584d363db9106bffa63))
* **models:** add equality methods to Job, RetryPolicy, UniquePolicy ([c727c47](https://github.com/openjobspec/ojs-ruby-sdk/commit/c727c47f5b4c9d11e46115a5b66654af5e664301))
* **models:** add to_hash serialization to Event and QueueStats ([4a63d38](https://github.com/openjobspec/ojs-ruby-sdk/commit/4a63d38107b924233f0008d55c1a7b88c22c2795))
* **ojs:** add top-level module and public API ([4e202c3](https://github.com/openjobspec/ojs-ruby-sdk/commit/4e202c3cc3dece1ad5cc8d8d9c55792b2f2c8fca))
* **otel:** add OpenTelemetry tracing middleware ([68fd8c6](https://github.com/openjobspec/ojs-ruby-sdk/commit/68fd8c69c6568b7a887f5720e5c4f1d4c0c2e434))
* **testing:** add fake mode and test assertion helpers ([36c372d](https://github.com/openjobspec/ojs-ruby-sdk/commit/36c372d2448d243c282ddcef251e40b473800ffb))
* **testing:** add FakeTransport for in-memory client testing ([7fd913a](https://github.com/openjobspec/ojs-ruby-sdk/commit/7fd913a493d285000bc0216ac4515249c31abd16))
* **transport:** add absolute path support to HTTP transport ([a2b23c9](https://github.com/openjobspec/ojs-ruby-sdk/commit/a2b23c993acffd82eaca9d7c3f0e1f4a5380421d))
* **transport:** add HTTP transport layer ([f135638](https://github.com/openjobspec/ojs-ruby-sdk/commit/f1356387258b4587a5f57de1d4c052a87050aff3))
* **transport:** parse rate limit headers on 429 responses ([2ef2bd7](https://github.com/openjobspec/ojs-ruby-sdk/commit/2ef2bd7624e0081ccba36192e29dba0e948d4982))
* **worker:** add pluggable logger ([0d8859d](https://github.com/openjobspec/ojs-ruby-sdk/commit/0d8859d1c8a1402c5067ce84ae91b9c0d0d45fe1))
* **worker:** add thread-pool worker with middleware support ([55aab7f](https://github.com/openjobspec/ojs-ruby-sdk/commit/55aab7f26cd5f0d99f3c8332d84904844f440873))
* **worker:** add worker identity and heartbeat state changes ([a5d32e4](https://github.com/openjobspec/ojs-ruby-sdk/commit/a5d32e4637fbfc0ef9291675bfea75939524f24a))
* **worker:** align error format with OJS wire protocol ([e05f628](https://github.com/openjobspec/ojs-ruby-sdk/commit/e05f6285d63aa5e39af660a511fd696e417031bf))


### Bug Fixes

* **transport:** raise on malformed JSON in success responses ([7f4fd09](https://github.com/openjobspec/ojs-ruby-sdk/commit/7f4fd09400a3e74c280aa0ac860a84e71a07db5e))
* **transport:** retry once on stale HTTP connection ([a92a019](https://github.com/openjobspec/ojs-ruby-sdk/commit/a92a0193766cc1c5bd8ccd19cde78142c55ee07f))
* **worker:** account for active jobs in fetch slot calculation ([4144048](https://github.com/openjobspec/ojs-ruby-sdk/commit/414404848bcad99145d1e0dfdb1eb80b0433c95e))
* **worker:** rescue StandardError instead of bare rescue ([b437a4b](https://github.com/openjobspec/ojs-ruby-sdk/commit/b437a4b09d7073340a37a0b21a8c475317dfdb6f))
* **worker:** resolve race condition and threading issues ([7fd803c](https://github.com/openjobspec/ojs-ruby-sdk/commit/7fd803cea5600e325ee5cc2a3713a472bcaa42c6))


### Performance Improvements

* **transport:** add persistent HTTP connections with keep-alive ([6962399](https://github.com/openjobspec/ojs-ruby-sdk/commit/69623999f30292273db84a10b4f70bc81264f69f))

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
