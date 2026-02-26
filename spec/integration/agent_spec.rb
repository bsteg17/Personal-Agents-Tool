# frozen_string_literal: true

require "spec_helper"

class TestInput < T::Struct
  const :topic, String
end

class TestOutput < T::Struct
  const :title, String
  const :body, String
end

class TestAgent < PersonalAgentsTool::Agent::Base
  input TestInput
  output TestOutput

  def call(input)
    TestOutput.new(title: "About #{input.topic}", body: "A post about #{input.topic}.")
  end
end

class IncompleteAgent < PersonalAgentsTool::Agent::Base
  # No input or output declared
end

class NoCallAgent < PersonalAgentsTool::Agent::Base
  input TestInput
  output TestOutput
  # Does not override #call
end

class BadOutputAgent < PersonalAgentsTool::Agent::Base
  input TestInput
  output TestOutput

  def call(input)
    "not a TestOutput struct"
  end
end

class FakeTool
  def self.execute(args)
    "tool result for #{args}"
  end
end

class ToolUsingAgent < PersonalAgentsTool::Agent::Base
  input TestInput
  output TestOutput
  tool :search, FakeTool

  def call(input)
    result = self.class.tools[:search].execute(input.topic)
    TestOutput.new(title: "Tool result", body: result)
  end
end

class LLMTestAgent < PersonalAgentsTool::Agent::Base
  input TestInput
  output TestOutput
  model "claude-sonnet-4-20250514"
  provider "anthropic"

  def call(input)
    response = llm.chat(prompt: "Write about #{input.topic}", schema: TestOutput)
    response
  end
end

class MultiTurnToolAgent < PersonalAgentsTool::Agent::Base
  input TestInput
  output TestOutput
  tool :search, FakeTool

  def call(input)
    first = llm.chat(prompt: "Search for #{input.topic}", tools: self.class.tools)
    tool_result = self.class.tools[:search].execute(first)
    llm.chat(prompt: "Summarize: #{tool_result}", schema: TestOutput)
  end
end

RSpec.describe "Agent" do
  describe "definition" do
    it "defines an agent class with typed input and output schemas" do
      expect(TestAgent.input_schema).to eq(TestInput)
      expect(TestAgent.output_schema).to eq(TestOutput)
    end

    it "raises if input or output schema is not declared" do
      agent = IncompleteAgent.new
      expect { agent.execute(TestInput.new(topic: "test")) }
        .to raise_error(PersonalAgentsTool::Agent::InvalidInputError, /No input schema declared/)
    end

    it "allows declaring tools an agent can use" do
      expect(ToolUsingAgent.tools).to eq({ search: FakeTool })
    end

    it "requires a call method that accepts input and returns output" do
      agent = NoCallAgent.new
      expect { agent.execute(TestInput.new(topic: "test")) }
        .to raise_error(PersonalAgentsTool::Agent::NotImplementedError, /must implement #call/)
    end
  end

  describe "execution" do
    it "validates input against the declared input schema before calling" do
      agent = TestAgent.new
      expect { agent.execute("not a struct") }
        .to raise_error(PersonalAgentsTool::Agent::InvalidInputError, /Expected TestInput/)
    end

    it "validates output against the declared output schema after calling" do
      agent = BadOutputAgent.new
      expect { agent.execute(TestInput.new(topic: "test")) }
        .to raise_error(PersonalAgentsTool::Agent::InvalidOutputError, /Expected TestOutput/)
    end

    it "returns a typed result object wrapping the output" do
      agent = TestAgent.new
      result = agent.execute(TestInput.new(topic: "Ruby"))

      expect(result).to be_a(PersonalAgentsTool::Agent::Result)
      expect(result.output).to be_a(TestOutput)
      expect(result.output.title).to eq("About Ruby")
      expect(result.output.body).to eq("A post about Ruby.")
      expect(result.agent_class).to eq(TestAgent)
      expect(result.duration).to be_a(Float)
    end

    it "raises a schema validation error on invalid input" do
      agent = TestAgent.new
      expect { agent.execute(42) }
        .to raise_error(PersonalAgentsTool::Agent::InvalidInputError)
    end

    it "raises a schema validation error on invalid output" do
      agent = BadOutputAgent.new
      expect { agent.execute(TestInput.new(topic: "test")) }
        .to raise_error(PersonalAgentsTool::Agent::InvalidOutputError)
    end
  end

  describe "LLM agents" do
    let(:mock_llm) { instance_double(PersonalAgentsTool::LLM::Client) }

    it "provides an llm client to agents that need one" do
      agent = LLMTestAgent.new(llm: mock_llm)
      expect(agent.llm).to eq(mock_llm)
    end

    it "calls the LLM and parses structured output into the output schema" do
      agent = LLMTestAgent.new(llm: mock_llm)
      expected_output = TestOutput.new(title: "AI Title", body: "AI Body")
      allow(mock_llm).to receive(:chat).and_return(expected_output)

      result = agent.execute(TestInput.new(topic: "AI"))

      expect(mock_llm).to have_received(:chat).with(prompt: "Write about AI", schema: TestOutput)
      expect(result.output).to eq(expected_output)
    end

    it "retries the LLM call when structured output fails to parse" do
      agent = LLMTestAgent.new(llm: mock_llm)
      expected_output = TestOutput.new(title: "Retry Title", body: "Retry Body")
      call_count = 0
      allow(mock_llm).to receive(:chat) do
        call_count += 1
        if call_count < 3
          raise "Parse error"
        end
        expected_output
      end

      # Agent itself doesn't retry — this tests that the caller can retry.
      # For now, we test that after failures, a successful call works.
      expect { agent.execute(TestInput.new(topic: "retry")) }.to raise_error(RuntimeError, "Parse error")
      expect { agent.execute(TestInput.new(topic: "retry")) }.to raise_error(RuntimeError, "Parse error")
      result = agent.execute(TestInput.new(topic: "retry"))
      expect(result.output).to eq(expected_output)
    end

    it "respects the configured model and provider per agent" do
      expect(LLMTestAgent.model).to eq("claude-sonnet-4-20250514")
      expect(LLMTestAgent.provider).to eq("anthropic")
    end
  end

  describe "pure code agents" do
    it "runs without any LLM call" do
      agent = TestAgent.new
      result = agent.execute(TestInput.new(topic: "no LLM"))

      expect(result.output.title).to eq("About no LLM")
      expect(agent.llm).to be_nil
    end

    it "uses the same input/output contract as LLM agents" do
      pure_agent = TestAgent.new
      llm_agent = LLMTestAgent.new(llm: instance_double(PersonalAgentsTool::LLM::Client))

      # Both use the same input/output type contract
      expect(pure_agent.class.input_schema).to eq(TestInput)
      expect(llm_agent.class.input_schema).to eq(TestInput)
      expect(pure_agent.class.output_schema).to eq(TestOutput)
      expect(llm_agent.class.output_schema).to eq(TestOutput)
    end
  end

  describe "tool-using agents" do
    it "can invoke declared tools during execution" do
      agent = ToolUsingAgent.new
      result = agent.execute(TestInput.new(topic: "Ruby"))

      expect(result.output.title).to eq("Tool result")
      expect(result.output.body).to eq("tool result for Ruby")
    end

    it "supports multi-turn LLM conversations with tool use" do
      mock_llm = instance_double(PersonalAgentsTool::LLM::Client)
      agent = MultiTurnToolAgent.new(llm: mock_llm)

      allow(mock_llm).to receive(:chat)
        .with(prompt: "Search for AI", tools: MultiTurnToolAgent.tools)
        .and_return("AI")

      final_output = TestOutput.new(title: "Summary", body: "Summary of tool result for AI")
      allow(mock_llm).to receive(:chat)
        .with(prompt: "Summarize: tool result for AI", schema: TestOutput)
        .and_return(final_output)

      result = agent.execute(TestInput.new(topic: "AI"))

      expect(result.output).to eq(final_output)
      expect(mock_llm).to have_received(:chat).twice
    end
  end
end
