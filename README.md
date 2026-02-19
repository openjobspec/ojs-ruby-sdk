# OJS Ruby SDK

[![CI](https://github.com/openjobspec/ojs-ruby-sdk/actions/workflows/test.yml/badge.svg)](https://github.com/openjobspec/ojs-ruby-sdk/actions/workflows/test.yml)
[![Gem Version](https://badge.fury.io/rb/ojs.svg)](https://rubygems.org/gems/ojs)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.2-ruby.svg)](https://www.ruby-lang.org/)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

Official Ruby SDK for the [Open Job Spec (OJS)](https://openjobspec.org) protocol.

**Zero runtime dependencies.** Uses only `net/http` and `json` from the Ruby standard library.

> 🎮 **New to OJS?** Try the [OJS Playground](https://github.com/openjobspec/ojs-playground) for an interactive exploration environment.

> **🚀 Try it now:** [Open in Playground](https://playground.openjobspec.org?lang=ruby) · [Run on CodeSandbox](https://codesandbox.io/p/sandbox/openjobspec-ruby-quickstart) · [Docker Quickstart](https://github.com/openjobspec/openjobspec/blob/main/docker-compose.quickstart.yml)

## Requirements

- Ruby 3.2+

## Installation

Add to your Gemfile:

```ruby
gem "ojs"
```

Or install directly:

```
gem install ojs
```

## Quick Start

### Client (Producer)

```ruby
require "ojs"

client = OJS::Client.new("http://localhost:8080")

# Simple enqueue — keyword args become the job payload
job = client.enqueue("email.send", to: "user@example.com")
puts job.id  # => "019461a8-..."

# Enqueue with options
job = client.enqueue("report.generate", { id: 42 },
  queue: "reports",
  delay: "5m",
  retry: OJS::RetryPolicy.new(max_attempts: 5),
  unique: OJS::UniquePolicy.new(keys: ["type", "args"], period: "PT1H")
)

# Batch enqueue
jobs = client.enqueue_batch([
  { type: "email.send", args: { to: "a@example.com" } },
  { type: "email.send", args: { to: "b@example.com" } },
])
```

### Worker (Consumer)

```ruby
require "ojs"

worker = OJS::Worker.new("http://localhost:8080",
  queues: %w[default email],
  concurrency: 10
)

worker.register("email.send") do |ctx|
  to = ctx.job.args["to"]
  result = send_email(to)
  { message_id: result.id }
end

# Middleware (Sidekiq/Rack-style)
worker.use("logging") do |ctx, &nxt|
  puts "Processing #{ctx.job.type}"
  start = Time.now
  result = nxt.call
  puts "Done in #{Time.now - start}s"
  result
end

worker.start  # Blocks until SIGTERM/SIGINT
```

### Workflows

```ruby
# Chain (sequential)
client.workflow(OJS.chain(
  OJS::Step.new(type: "data.fetch", args: { url: "https://..." }),
  OJS::Step.new(type: "data.transform", args: { format: "csv" }),
  OJS::Step.new(type: "data.upload", args: { bucket: "results" }),
  name: "etl-pipeline"
))

# Group (parallel)
client.workflow(OJS.group(
  OJS::Step.new(type: "export.csv", args: { report_id: 1 }),
  OJS::Step.new(type: "export.pdf", args: { report_id: 1 }),
  name: "multi-export"
))

# Batch (parallel + callbacks)
client.workflow(OJS.batch(
  [
    OJS::Step.new(type: "email.send", args: { to: "a@example.com" }),
    OJS::Step.new(type: "email.send", args: { to: "b@example.com" }),
  ],
  name: "bulk-send",
  on_complete: OJS::Step.new(type: "batch.report", args: {}),
  on_failure: OJS::Step.new(type: "batch.alert", args: {})
))
```

## API Reference

### OJS::Client

| Method | Description |
|--------|-------------|
| `enqueue(type, args, **opts)` | Enqueue a single job |
| `enqueue_batch(jobs)` | Enqueue multiple jobs atomically |
| `workflow(definition)` | Create and start a workflow |
| `get_job(id)` | Get a job by ID |
| `cancel_job(id)` | Cancel a job |
| `queues` | List all queues |
| `queue_stats(name)` | Get queue statistics |
| `pause_queue(name)` | Pause a queue |
| `resume_queue(name)` | Resume a paused queue |
| `dead_letter_jobs` | List dead letter jobs |
| `retry_dead_letter(id)` | Retry a dead letter job |
| `discard_dead_letter(id)` | Discard a dead letter job |
| `health` | Server health check |

### Enqueue Options

| Option | Type | Description |
|--------|------|-------------|
| `queue:` | String | Target queue (default: `"default"`) |
| `delay:` | String | Delay before execution (`"5m"`, `"1h"`, `"PT30S"`) |
| `scheduled_at:` | String | ISO 8601 timestamp for scheduled execution |
| `priority:` | Integer | Job priority (higher = higher priority) |
| `timeout:` | Integer | Max execution time in seconds |
| `retry:` | RetryPolicy | Retry configuration |
| `unique:` | UniquePolicy | Deduplication configuration |
| `meta:` | Hash | Arbitrary metadata |
| `expires_at:` | String | ISO 8601 expiration timestamp |

### OJS::RetryPolicy

```ruby
OJS::RetryPolicy.new(
  max_attempts: 5,              # Total attempts (default: 3)
  initial_interval: "PT2S",     # First retry delay (default: "PT1S")
  backoff_coefficient: 2.0,     # Multiplier per attempt (default: 2.0)
  max_interval: "PT10M",        # Max delay cap (default: "PT5M")
  jitter: true,                 # Randomize delays (default: true)
  non_retryable_errors: ["validation.*"],
  on_exhaustion: "dead_letter"  # "discard" (default) or "dead_letter"
)
```

### OJS::UniquePolicy

```ruby
OJS::UniquePolicy.new(
  keys: ["type", "queue", "args"],  # Uniqueness dimensions
  args_keys: ["user_id"],           # Filter args keys
  period: "PT1H",                   # TTL window
  on_conflict: "reject"             # "reject", "replace", "ignore"
)
```

### OJS::Worker

| Method | Description |
|--------|-------------|
| `register(type, &handler)` | Register a handler for a job type |
| `use(name, &block)` | Add middleware |
| `start` | Start processing (blocks) |
| `stop` | Graceful shutdown |
| `quiet` | Stop fetching, finish in-flight |

### Worker Options

| Option | Default | Description |
|--------|---------|-------------|
| `queues:` | `["default"]` | Queues to consume from |
| `concurrency:` | `5` | Number of worker threads |
| `poll_interval:` | `2.0` | Seconds between polls |
| `heartbeat_interval:` | `15.0` | Seconds between heartbeats |
| `shutdown_timeout:` | `25.0` | Max seconds to wait on shutdown |
| `logger:` | `Logger.new($stdout)` | Logger instance for worker output |

### Middleware

Middleware follows the Sidekiq/Rack yield-based pattern:

```ruby
worker.use("timing") do |ctx, &nxt|
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result = nxt.call
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  puts "#{ctx.job.type} completed in #{elapsed.round(3)}s"
  result
end
```

The middleware chain supports `add`, `prepend`, `insert_before`, `insert_after`, and `remove` for ordering control.

### Error Handling

All errors inherit from `OJS::Error`:

| Error Class | Code | Retryable? |
|-------------|------|------------|
| `OJS::ValidationError` | `invalid_request` | No |
| `OJS::NotFoundError` | `not_found` | No |
| `OJS::ConflictError` | `duplicate` | No |
| `OJS::QueuePausedError` | `queue_paused` | Yes |
| `OJS::RateLimitError` | `rate_limited` | Yes |
| `OJS::ServerError` | `backend_error` | Yes |
| `OJS::TimeoutError` | `timeout` | Yes |
| `OJS::ConnectionError` | — | Yes |

```ruby
begin
  client.enqueue("email.send", to: "user@example.com")
rescue OJS::ConflictError => e
  puts "Duplicate job: #{e.existing_job_id}"
rescue OJS::RateLimitError => e
  sleep(e.retry_after || 5)
  retry
rescue OJS::Error => e
  puts "#{e.code}: #{e.message} (retryable: #{e.retryable?})"
end
```

## Migrating from Sidekiq

See [examples/sidekiq_migration.rb](examples/sidekiq_migration.rb) for a complete migration guide.

## Testing

The SDK includes a built-in testing module that lets you test job-enqueuing code without a running OJS server.

### Setup

```ruby
require "ojs"
require "ojs/testing"

# Create a test client with a fake in-memory transport
transport = OJS::Testing.fake_transport
client = OJS::Client.new("http://unused", transport: transport)
```

### Asserting Enqueued Jobs

```ruby
# Enqueue some jobs in your code under test
client.enqueue("email.send", to: "user@example.com")
client.enqueue("report.generate", { id: 42 }, queue: "reports")

# Assert jobs were enqueued
OJS::Testing.assert_enqueued("email.send")
OJS::Testing.assert_enqueued("email.send", count: 1)
OJS::Testing.assert_enqueued_on("reports", "report.generate")

# Inspect enqueued jobs directly
store = OJS::Testing.store
store.enqueued          # => [Job, Job, ...]
store.enqueued_types    # => ["email.send", "report.generate"]
store.jobs_for("email.send")  # => [Job]
```

### Draining Jobs

```ruby
# Register handlers and drain enqueued jobs synchronously
OJS::Testing.drain("email.send") do |job|
  EmailService.deliver(job.args.first)
end
```

### Cleanup

```ruby
# In your test teardown
OJS::Testing.store.clear
```

## Development

```bash
bundle install
bundle exec rspec
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for more details.

## License

Apache-2.0
