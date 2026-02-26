# Personal-Agents-Tool

A bespoke Ruby library for building and orchestrating multi-agent workflows. Built with Sorbet type checking.

## What This Is

A personal toolkit for composing **independent, self-contained agents** into DAG-based workflows. Each agent receives structured input, does its work (LLM call, API call, pure computation, or any combination), and produces structured output. Agents know nothing about each other — they're wired together by an orchestration layer.

## Architecture Decisions

### Interface: Ruby DSL (class-based agents, block DSL for workflows)

Agents are Ruby classes inheriting from a base class — this gives full Sorbet type safety on inputs, outputs, and the `call` method. Workflows are wired together using a block-based DSL for concise, readable DAG definitions.

```ruby
# Agents are classes with typed contracts
class DraftWriter < Agent::Base
  input  TopicInput
  output DraftOutput

  sig { override.params(input: TopicInput).returns(DraftOutput) }
  def call(input)
    llm.chat(prompt: "Write a blog post about #{input.topic}", schema: DraftOutput)
  end
end

# Workflows are wired with a block DSL
workflow :content_pipeline do
  step :draft,  agent: DraftWriter
  step :edit,   agent: Editor,        after: :draft
  step :images, agent: ImageGenerator, after: :draft
  step :format, agent: Formatter,     after: [:edit, :images]
end
```

### LLM Support: Multi-Provider (Claude, OpenAI, Gemini)

A unified LLM client interface supporting all three providers. Each agent can specify which provider/model to use, or inherit a default. The interface abstracts away provider differences while exposing provider-specific features when needed.

### Structured Output: Framework-Assisted

The framework provides structured output helpers — pass a Sorbet schema to the LLM client, and the framework handles parsing, validation, and retry on parse failure. Agents can opt out and handle parsing themselves when they need more control.

### Error Handling: Global Defaults with Per-Agent Overrides

Sensible defaults at the workflow level (3 retries, exponential backoff). Individual agents can override retry count, backoff strategy, and which errors are retriable.

### Persistence: Filesystem (JSON)

Each workflow run gets a directory. Each step's output is serialized to JSON. This enables:

- **Resumability** — if a pipeline crashes at step 5 of 8, resume from step 5 using persisted outputs from steps 1-4
- **Inspectability** — browse run directories to see exactly what each agent produced
- **Reproducibility** — re-run a single agent with its persisted input to debug or iterate

```
runs/
  content_pipeline_2026-02-26_001/
    metadata.json          # workflow config, status, timestamps
    steps/
      draft/
        input.json
        output.json
        status.json        # completed/failed/pending, retries, errors
      edit/
        input.json
        output.json
        status.json
      ...
```

## Core Concepts

### Agents as Independent Units

Each agent is a self-contained unit with:

- **Typed input schema** (`T::Struct`) — what it expects to receive
- **Typed output schema** (`T::Struct`) — what it produces
- **Execution logic** — LLM call, external API, multi-step tool-use loop, or pure Ruby
- **Retry configuration** — inherits workflow defaults, can override

Not every agent needs an LLM. Some are pure code (e.g., an ffmpeg wrapper, a file formatter). Some are single LLM calls with structured output. Some are multi-turn LLM conversations with tool use. The framework accommodates all of these uniformly.

### DAG-Based Orchestration

Agents are composed into directed acyclic graphs. The orchestrator:

- Runs agents in dependency order
- Parallelizes independent branches where possible
- Passes outputs from upstream agents as inputs to downstream agents
- Handles failures, retries, and resumption from persisted state

### Structured Data Flow

Agents communicate via Sorbet `T::Struct`s. The schema is the contract. If an agent produces valid output matching its schema, any downstream agent can consume it without knowing how it was produced.

## First Workflow: Content Pipeline

A simple 3-4 agent pipeline to prove out the framework:

1. **DraftWriter** — given a topic, drafts a blog post (LLM agent)
2. **Editor** — revises the draft for clarity and tone (LLM agent)
3. **ImageGenerator** — creates images to accompany the post (API agent)
4. **Formatter** — assembles final output with text + images (pure code agent)

This exercises all the key framework features: typed I/O, LLM calls, external APIs, pure code agents, parallel branches (edit + images), and DAG orchestration.

## Tech Stack

- **Ruby** with **Sorbet** for static type checking
- **Sorbet `T::Struct`** for all inter-agent schemas
- **Multi-provider LLM client** (Claude, OpenAI, Gemini) with unified interface
- **Filesystem persistence** (JSON) for workflow state and intermediate results

## Status

Design phase complete. Next step: implement core abstractions (`Agent::Base`, `Workflow`, LLM client interface) and build the content pipeline.
