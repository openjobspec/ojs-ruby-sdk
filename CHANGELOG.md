# Changelog

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

### Improvements
- Persistent HTTP connections with keep-alive (thread-safe via thread-local storage)
- Fixed race condition in Worker state checks (TOCTOU on @active_jobs)
- Fixed worker busy-wait: blocking Queue#pop replaces non-blocking pop + sleep
- Fixed signal handler deadlock risk (mutex acquisition in trap context)
- Fixed silent JSON parse errors on success responses (now raises OJS::Error)
- Fixed ValidationError constructor kwargs mutation
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
- Added CONTRIBUTING.md
