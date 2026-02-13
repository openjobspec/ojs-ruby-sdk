# Contributing to OJS Ruby SDK

Thank you for your interest in contributing to the OJS Ruby SDK!

## Requirements

- Ruby 3.2+
- Bundler

## Setup

```bash
git clone https://github.com/openjobspec/ojs-ruby-sdk.git
cd ojs-ruby-sdk
bundle install
```

## Running Tests

```bash
# Run all unit tests
bundle exec rspec

# Run a specific test file
bundle exec rspec spec/client_spec.rb

# Run integration tests (requires a running OJS server)
OJS_INTEGRATION=1 OJS_URL=http://localhost:8080 bundle exec rspec spec/integration/
```

## Code Style

- Use `frozen_string_literal: true` in all Ruby files
- Follow existing naming conventions and patterns
- Keep zero runtime dependencies — only use Ruby standard library
- Add YARD-style documentation for public methods

## Making Changes

1. Fork the repository and create a feature branch
2. Write tests for your changes
3. Ensure all tests pass: `bundle exec rspec`
4. Update CHANGELOG.md with a brief description of your change
5. Submit a pull request

## Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` — New features
- `fix:` — Bug fixes
- `test:` — Test additions or corrections
- `docs:` — Documentation changes
- `chore:` — Maintenance tasks

## Reporting Issues

Please open an issue at https://github.com/openjobspec/ojs-ruby-sdk/issues with:

- Ruby version (`ruby -v`)
- OJS server version
- Steps to reproduce
- Expected vs actual behavior
