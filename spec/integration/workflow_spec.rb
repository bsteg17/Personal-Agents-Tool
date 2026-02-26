# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Workflow" do
  describe "definition" do
    it "defines a workflow with a name using the block DSL"
    it "declares steps with agent classes"
    it "declares step dependencies via the after: option"
    it "supports depending on multiple upstream steps"
    it "raises on circular dependencies"
    it "raises if a step references a nonexistent dependency"
  end

  describe "DAG execution" do
    it "runs steps in dependency order"
    it "parallelizes independent branches"
    it "passes upstream step outputs as inputs to downstream steps"
    it "merges outputs from multiple upstream steps when a step depends on several"
    it "runs a single-step workflow"
    it "runs a linear multi-step workflow end to end"
    it "runs a diamond-shaped DAG (fork and join)"
  end

  describe "error handling" do
    it "retries a failed step up to the global default retry count"
    it "respects per-agent retry count overrides"
    it "uses exponential backoff between retries"
    it "marks the step as failed after exhausting retries"
    it "does not run downstream steps when an upstream step fails"
    it "reports which step failed and the error details"
  end
end
