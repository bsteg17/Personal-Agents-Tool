# frozen_string_literal: true

require "spec_helper"

RSpec.describe "LLM Client" do
  describe "unified interface" do
    it "exposes a chat method that accepts a prompt and returns a response"
    it "accepts an optional output schema for structured output"
    it "accepts an optional system prompt"
    it "accepts an optional list of tools"
  end

  describe "provider support" do
    it "supports the Claude provider"
    it "supports the OpenAI provider"
    it "supports the Gemini provider"
    it "raises on unknown provider"
  end

  describe "structured output" do
    it "parses LLM response into the given Sorbet T::Struct schema"
    it "retries when the LLM response fails to parse"
    it "raises after exhausting parse retries"
    it "allows agents to opt out and receive raw response text"
  end

  describe "tool use" do
    it "sends tool definitions to the LLM"
    it "executes tool calls returned by the LLM"
    it "sends tool results back and continues the conversation"
    it "supports multi-turn tool use loops until the LLM signals completion"
  end
end
