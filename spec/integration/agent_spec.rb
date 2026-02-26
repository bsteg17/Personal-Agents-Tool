# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Agent" do
  describe "definition" do
    it "defines an agent class with typed input and output schemas"
    it "raises if input or output schema is not declared"
    it "allows declaring tools an agent can use"
    it "requires a call method that accepts input and returns output"
  end

  describe "execution" do
    it "validates input against the declared input schema before calling"
    it "validates output against the declared output schema after calling"
    it "returns a typed result object wrapping the output"
    it "raises a schema validation error on invalid input"
    it "raises a schema validation error on invalid output"
  end

  describe "LLM agents" do
    it "provides an llm client to agents that need one"
    it "calls the LLM and parses structured output into the output schema"
    it "retries the LLM call when structured output fails to parse"
    it "respects the configured model and provider per agent"
  end

  describe "pure code agents" do
    it "runs without any LLM call"
    it "uses the same input/output contract as LLM agents"
  end

  describe "tool-using agents" do
    it "can invoke declared tools during execution"
    it "supports multi-turn LLM conversations with tool use"
  end
end
