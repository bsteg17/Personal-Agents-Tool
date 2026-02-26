# CLAUDE.md

## Project

Personal-Agents-Tool — a Ruby/Sorbet library for building and orchestrating multi-agent workflows.

## Setup

- Ruby 3.3.10 via rbenv
- `bundle install` to install dependencies
- `bundle exec rspec` to run tests

## Testing Rules

- **Always run `bundle exec rspec` before and after making changes** to verify nothing is broken.
- **When adding new functionality, fill in the corresponding pending spec(s)** in `spec/integration/` with real test logic. Do not leave specs pending if the feature they describe has been implemented.
- **When adding functionality not yet covered by a spec, add new specs** that cover it. Every public-facing behavior should have a corresponding integration spec.
- **Never delete or weaken a passing spec** unless the underlying behavior is intentionally being removed or changed, and the user has approved it.
- Specs live in `spec/integration/`. Use `spec/spec_helper.rb` for shared config.
- Prefer integration-level specs that test real behavior over mocks. Use mocks/stubs only for external API calls (LLM providers, image generation APIs).

## Code Style

- Use Sorbet type signatures (`sig`) on all public methods.
- Use `T::Struct` for all inter-agent data schemas.
- Follow existing patterns in the codebase. Check similar files before writing new ones.
- `frozen_string_literal: true` at the top of every Ruby file.
