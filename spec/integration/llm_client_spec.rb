# frozen_string_literal: true

require "spec_helper"

class LLMTestOutput < T::Struct
  const :title, String
  const :body, String
end

class LLMTestTool < PersonalAgentsTool::Tool::Base
  extend T::Sig

  sig { override.params(args: T.untyped).returns(String) }
  def self.execute(args)
    "result for #{args}"
  end
end

RSpec.describe "LLM Client" do
  def new_client(provider: "claude", model: "claude-sonnet-4-20250514", max_retries: 3)
    PersonalAgentsTool::LLM::Client.new(provider: provider, model: model, max_retries: max_retries)
  end

  def stub_provider(client, &block)
    allow(client.provider).to receive(:chat, &block)
  end

  def stub_provider_return(client, response)
    allow(client.provider).to receive(:chat).and_return(response)
  end

  def response(content: nil, tool_calls: [])
    PersonalAgentsTool::LLM::Response.new(content: content, tool_calls: tool_calls)
  end

  describe "unified interface" do
    it "exposes a chat method that accepts a prompt and returns a response" do
      client = new_client
      stub_provider_return(client, response(content: "Hello world"))

      result = client.chat(prompt: "Say hello")
      expect(result).to eq("Hello world")
    end

    it "accepts an optional output schema for structured output" do
      client = new_client
      stub_provider_return(client, response(content: '{"title":"Test","body":"Content"}'))

      result = client.chat(prompt: "Write something", schema: LLMTestOutput)
      expect(result).to be_a(LLMTestOutput)
      expect(result.title).to eq("Test")
    end

    it "accepts an optional system prompt" do
      client = new_client
      stub_provider_return(client, response(content: "Response"))

      result = client.chat(prompt: "Hello", system: "You are helpful")
      expect(result).to eq("Response")
      expect(client.provider).to have_received(:chat).with(
        messages: [
          { role: "system", content: "You are helpful" },
          { role: "user", content: "Hello" },
        ],
        model: "claude-sonnet-4-20250514",
      )
    end

    it "accepts an optional list of tools" do
      client = new_client
      tools = { search: LLMTestTool }
      stub_provider_return(client, response(content: "Done"))

      result = client.chat(prompt: "Find something", tools: tools)
      expect(result).to eq("Done")
      expect(client.provider).to have_received(:chat).with(
        messages: [{ role: "user", content: "Find something" }],
        model: "claude-sonnet-4-20250514",
        tools: tools,
      )
    end
  end

  describe "provider support" do
    it "supports the Claude provider" do
      client = new_client(provider: "claude")
      expect(client.provider).to be_a(PersonalAgentsTool::LLM::Providers::Claude)
    end

    it "supports the OpenAI provider" do
      client = new_client(provider: "openai", model: "gpt-4")
      expect(client.provider).to be_a(PersonalAgentsTool::LLM::Providers::OpenAI)
    end

    it "supports the Gemini provider" do
      client = new_client(provider: "gemini", model: "gemini-pro")
      expect(client.provider).to be_a(PersonalAgentsTool::LLM::Providers::Gemini)
    end

    it "raises on unknown provider" do
      expect {
        new_client(provider: "unknown", model: "test")
      }.to raise_error(PersonalAgentsTool::LLM::UnknownProviderError, /Unknown provider: unknown/)
    end
  end

  describe "structured output" do
    it "parses LLM response into the given Sorbet T::Struct schema" do
      client = new_client
      stub_provider_return(client, response(content: '{"title":"Parsed","body":"Structured output"}'))

      result = client.chat(prompt: "Generate", schema: LLMTestOutput)
      expect(result).to be_a(LLMTestOutput)
      expect(result.title).to eq("Parsed")
      expect(result.body).to eq("Structured output")
    end

    it "retries when the LLM response fails to parse" do
      client = new_client(max_retries: 3)
      call_count = 0
      stub_provider(client) do
        call_count += 1
        if call_count == 1
          response(content: "not valid json")
        else
          response(content: '{"title":"Retried","body":"Success"}')
        end
      end

      result = client.chat(prompt: "Generate", schema: LLMTestOutput)
      expect(result.title).to eq("Retried")
      expect(call_count).to eq(2)
    end

    it "raises after exhausting parse retries" do
      client = new_client(max_retries: 2)
      stub_provider_return(client, response(content: "not json"))

      expect {
        client.chat(prompt: "Generate", schema: LLMTestOutput)
      }.to raise_error(PersonalAgentsTool::LLM::ParseError, /Failed to parse structured output after 2 retries/)
    end

    it "allows agents to opt out and receive raw response text" do
      client = new_client
      stub_provider_return(client, response(content: "Just plain text"))

      result = client.chat(prompt: "Write freely")
      expect(result).to eq("Just plain text")
      expect(result).to be_a(String)
    end
  end

  describe "tool use" do
    let(:tools) { { search: LLMTestTool } }

    it "sends tool definitions to the LLM" do
      client = new_client
      stub_provider_return(client, response(content: "No tools needed"))

      client.chat(prompt: "Search", tools: tools)
      expect(client.provider).to have_received(:chat).with(
        messages: [{ role: "user", content: "Search" }],
        model: "claude-sonnet-4-20250514",
        tools: tools,
      )
    end

    it "executes tool calls returned by the LLM" do
      client = new_client
      call_count = 0
      stub_provider(client) do
        call_count += 1
        if call_count == 1
          response(content: nil, tool_calls: [PersonalAgentsTool::LLM::ToolCall.new(name: :search, arguments: "Ruby")])
        else
          response(content: "Found: result for Ruby")
        end
      end

      result = client.chat(prompt: "Search for Ruby", tools: tools)
      expect(result).to eq("Found: result for Ruby")
    end

    it "sends tool results back and continues the conversation" do
      client = new_client
      call_count = 0
      stub_provider(client) do |messages:, **_|
        call_count += 1
        if call_count == 1
          response(content: nil, tool_calls: [PersonalAgentsTool::LLM::ToolCall.new(name: :search, arguments: "test")])
        else
          tool_message = messages.find { |m| m[:role] == "tool" }
          response(content: "Got tool result: #{tool_message&.dig(:content)}")
        end
      end

      result = client.chat(prompt: "Use tool", tools: tools)
      expect(result).to eq("Got tool result: result for test")
    end

    it "supports multi-turn tool use loops until the LLM signals completion" do
      client = new_client
      call_count = 0
      stub_provider(client) do
        call_count += 1
        case call_count
        when 1
          response(content: nil, tool_calls: [PersonalAgentsTool::LLM::ToolCall.new(name: :search, arguments: "first")])
        when 2
          response(content: nil, tool_calls: [PersonalAgentsTool::LLM::ToolCall.new(name: :search, arguments: "second")])
        else
          response(content: "All done after 2 tool calls")
        end
      end

      result = client.chat(prompt: "Do research", tools: tools)
      expect(result).to eq("All done after 2 tool calls")
      expect(call_count).to eq(3)
    end
  end
end
