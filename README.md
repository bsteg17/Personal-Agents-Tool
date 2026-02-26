# Personal-Agents-Tool

A bespoke Ruby library for building and orchestrating multi-agent workflows. Built with Sorbet type checking.

## What This Is

A personal toolkit for composing **independent, self-contained agents** into DAG-based workflows. Each agent receives structured input, does its work (LLM call, API call, pure computation, or any combination), and produces structured output. Agents know nothing about each other — they're wired together by an orchestration layer.

## Core Concepts

### Agents as Independent Units

Each agent is a self-contained unit with:

- **Typed input schema** — what it expects to receive
- **Typed output schema** — what it produces
- **Execution logic** — could be an LLM call, an external API call, a multi-step tool-use loop, or pure Ruby code
- **Retry/validation logic** — if output doesn't match the schema or fails quality checks, retry with corrected inputs

Not every agent needs an LLM. Some are pure code (e.g., an ffmpeg wrapper, a job runner). Some are single LLM calls with structured output. Some are multi-turn LLM conversations with tool use. The framework should accommodate all of these uniformly.

### DAG-Based Orchestration

Agents are composed into directed acyclic graphs (DAGs). The orchestrator:

- Runs agents in dependency order
- Parallelizes independent branches where possible
- Passes outputs from upstream agents as inputs to downstream agents
- Handles failures, retries, and resumption (if the pipeline crashes at step N, resume from step N)

### Structured Data Flow

Agents communicate via typed data structures (Sorbet `T::Struct`s). The schema is the contract. If an agent produces valid output matching its schema, any downstream agent can consume it without knowing how it was produced.

## Inspirations & Design Space

Drawing from the spectrum of approaches discussed in the [design conversation](https://claude.ai/share/412db5fd-ef44-4ee0-bf00-ba49d4573608):

| Approach | Description |
|---|---|
| **Plain functions + queue** | Each agent is a Ruby method/class. Orchestration via a workflow engine. Maximum flexibility, no framework magic. |
| **Agent framework** | Declarative agent definitions (model, system prompt, tools, output schema). Framework handles tool-use loops, retries, structured output enforcement. |
| **Direct API calls** | Each agent is a prompt + schema + tool list. You control the LLM interaction directly. Most portable and testable. |
| **Hybrid (recommended)** | Match the tool to the agent's complexity. Simple agents are direct API calls. Complex multi-step agents get richer harnesses. Pure-code agents are just Ruby classes. All share the same input/output contract. |

## Example Use Case

A **script-to-film pipeline** with 8 agents forming a DAG:

```
Script Analyst → Art Director → Cinematographer → Prompt Engineer
    → Generator Orchestrator → Quality Control → Audio Mixer → Editor
```

Each agent is independently testable, swappable, and can use a different LLM (or no LLM at all). The QC agent feeds failures back to earlier agents for retry. The orchestrator handles parallelism and resumption.

## Tech Stack

- **Ruby** with **Sorbet** for static type checking
- Typed schemas (`T::Struct`) for all inter-agent data
- TBD: orchestration approach, LLM client, persistence layer

## Status

Early design phase. Next step: define the core abstractions (Agent, Workflow, Schema) and build a minimal working pipeline.
