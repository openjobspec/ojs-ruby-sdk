# Changelog

## 0.1.0 (Unreleased)

- Initial release
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
