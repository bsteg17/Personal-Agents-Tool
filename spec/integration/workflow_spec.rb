# frozen_string_literal: true

require "spec_helper"

module WorkflowTestHelpers
  class SimpleInput < T::Struct
    const :text, String
  end

  class SimpleOutput < T::Struct
    const :text, String
  end

  class PassThroughAgent < PersonalAgentsTool::Agent::Base
    input SimpleInput
    output SimpleOutput

    def call(input)
      SimpleOutput.new(text: input.text)
    end
  end

  class AppendAgent < PersonalAgentsTool::Agent::Base
    input SimpleOutput
    output SimpleOutput

    def call(input)
      SimpleOutput.new(text: "#{input.text}:appended")
    end
  end

  class UpperAgent < PersonalAgentsTool::Agent::Base
    input SimpleOutput
    output SimpleOutput

    def call(input)
      SimpleOutput.new(text: input.text.upcase)
    end
  end

  class MergeAgent < PersonalAgentsTool::Agent::Base
    input PersonalAgentsTool::Workflow::MergedInput
    output SimpleOutput

    def call(input)
      merged = input.outputs.map { |k, v| "#{k}=#{v.text}" }.sort.join(",")
      SimpleOutput.new(text: merged)
    end
  end

  class FailingAgent < PersonalAgentsTool::Agent::Base
    input SimpleInput
    output SimpleOutput

    def call(_input)
      raise "I always fail"
    end
  end

  class CountingFailAgent < PersonalAgentsTool::Agent::Base
    input SimpleInput
    output SimpleOutput

    attr_reader :attempts

    def initialize(llm: nil, fail_times: 2)
      super(llm: llm)
      @fail_times = fail_times
      @attempts = 0
      @mutex = Mutex.new
    end

    def call(input)
      @mutex.synchronize { @attempts += 1 }
      if @attempts <= @fail_times
        raise "Fail attempt #{@attempts}"
      end
      SimpleOutput.new(text: "#{input.text}:recovered")
    end
  end
end

RSpec.describe "Workflow" do
  include WorkflowTestHelpers

  let(:simple_input) { WorkflowTestHelpers::SimpleInput }
  let(:pass_through) { WorkflowTestHelpers::PassThroughAgent }
  let(:append_agent) { WorkflowTestHelpers::AppendAgent }
  let(:upper_agent) { WorkflowTestHelpers::UpperAgent }
  let(:merge_agent) { WorkflowTestHelpers::MergeAgent }
  let(:failing_agent) { WorkflowTestHelpers::FailingAgent }
  let(:counting_fail) { WorkflowTestHelpers::CountingFailAgent }

  describe "definition" do
    it "defines a workflow with a name using the block DSL" do
      workflow = PersonalAgentsTool::Workflow::Definition.define("my_workflow") do |w|
        w.step :first, pass_through
      end

      expect(workflow.name).to eq("my_workflow")
    end

    it "declares steps with agent classes" do
      workflow = PersonalAgentsTool::Workflow::Definition.define("test") do |w|
        w.step :a, pass_through
        w.step :b, append_agent
      end

      expect(workflow.steps.keys).to contain_exactly(:a, :b)
      expect(workflow.steps[:a].agent_class).to eq(pass_through)
      expect(workflow.steps[:b].agent_class).to eq(append_agent)
    end

    it "declares step dependencies via the after: option" do
      workflow = PersonalAgentsTool::Workflow::Definition.define("test") do |w|
        w.step :a, pass_through
        w.step :b, append_agent, after: :a
      end

      expect(workflow.steps[:b].after).to eq([:a])
    end

    it "supports depending on multiple upstream steps" do
      workflow = PersonalAgentsTool::Workflow::Definition.define("test") do |w|
        w.step :a, pass_through
        w.step :b, pass_through
        w.step :c, merge_agent, after: [:a, :b]
      end

      expect(workflow.steps[:c].after).to contain_exactly(:a, :b)
    end

    it "raises on circular dependencies" do
      expect do
        PersonalAgentsTool::Workflow::Definition.define("test") do |w|
          w.step :a, pass_through, after: :b
          w.step :b, pass_through, after: :a
        end
      end.to raise_error(PersonalAgentsTool::Workflow::CircularDependencyError)
    end

    it "raises if a step references a nonexistent dependency" do
      expect do
        PersonalAgentsTool::Workflow::Definition.define("test") do |w|
          w.step :a, pass_through, after: :nonexistent
        end
      end.to raise_error(PersonalAgentsTool::Workflow::MissingDependencyError)
    end
  end

  describe "DAG execution" do
    it "runs steps in dependency order" do
      workflow = PersonalAgentsTool::Workflow::Definition.define("pipeline") do |w|
        w.step :start, pass_through
        w.step :finish, append_agent, after: :start
      end

      executor = PersonalAgentsTool::Workflow::Executor.new(workflow)
      result = executor.run(WorkflowTestHelpers::SimpleInput.new(text: "hello"))

      expect(result.success).to be true
      expect(result.step_results[:finish].output.text).to eq("hello:appended")
    end

    it "parallelizes independent branches" do
      mutex = Mutex.new
      cv = ConditionVariable.new
      count = 0

      agent_a = pass_through.new
      agent_b = pass_through.new

      allow(agent_a).to receive(:call).and_wrap_original do |m, input|
        mutex.synchronize do
          count += 1
          cv.signal
          cv.wait(mutex) until count >= 2
        end
        m.call(input)
      end

      allow(agent_b).to receive(:call).and_wrap_original do |m, input|
        mutex.synchronize do
          count += 1
          cv.signal
          cv.wait(mutex) until count >= 2
        end
        m.call(input)
      end

      workflow = PersonalAgentsTool::Workflow::Definition.define("parallel") do |w|
        w.step :a, pass_through
        w.step :b, pass_through
      end

      executor = PersonalAgentsTool::Workflow::Executor.new(
        workflow,
        agents: { a: agent_a, b: agent_b }
      )
      result = executor.run(WorkflowTestHelpers::SimpleInput.new(text: "test"))

      expect(result.success).to be true
      expect(result.step_results.keys).to contain_exactly(:a, :b)
    end

    it "passes upstream step outputs as inputs to downstream steps" do
      workflow = PersonalAgentsTool::Workflow::Definition.define("chain") do |w|
        w.step :first, pass_through
        w.step :second, append_agent, after: :first
      end

      executor = PersonalAgentsTool::Workflow::Executor.new(workflow)
      result = executor.run(WorkflowTestHelpers::SimpleInput.new(text: "data"))

      expect(result.success).to be true
      expect(result.step_results[:second].output.text).to eq("data:appended")
    end

    it "merges outputs from multiple upstream steps when a step depends on several" do
      workflow = PersonalAgentsTool::Workflow::Definition.define("merge") do |w|
        w.step :a, pass_through
        w.step :b, pass_through
        w.step :c, merge_agent, after: [:a, :b]
      end

      executor = PersonalAgentsTool::Workflow::Executor.new(workflow)
      result = executor.run(WorkflowTestHelpers::SimpleInput.new(text: "val"))

      expect(result.success).to be true
      expect(result.step_results[:c].output.text).to eq("a=val,b=val")
    end

    it "runs a single-step workflow" do
      workflow = PersonalAgentsTool::Workflow::Definition.define("single") do |w|
        w.step :only, pass_through
      end

      executor = PersonalAgentsTool::Workflow::Executor.new(workflow)
      result = executor.run(WorkflowTestHelpers::SimpleInput.new(text: "solo"))

      expect(result.success).to be true
      expect(result.step_results[:only].output.text).to eq("solo")
      expect(result.duration).to be > 0
    end

    it "runs a linear multi-step workflow end to end" do
      workflow = PersonalAgentsTool::Workflow::Definition.define("linear") do |w|
        w.step :a, pass_through
        w.step :b, append_agent, after: :a
        w.step :c, append_agent, after: :b
      end

      executor = PersonalAgentsTool::Workflow::Executor.new(workflow)
      result = executor.run(WorkflowTestHelpers::SimpleInput.new(text: "start"))

      expect(result.success).to be true
      expect(result.step_results[:c].output.text).to eq("start:appended:appended")
    end

    it "runs a diamond-shaped DAG (fork and join)" do
      workflow = PersonalAgentsTool::Workflow::Definition.define("diamond") do |w|
        w.step :root, pass_through
        w.step :left, append_agent, after: :root
        w.step :right, upper_agent, after: :root
        w.step :join, merge_agent, after: [:left, :right]
      end

      executor = PersonalAgentsTool::Workflow::Executor.new(workflow)
      result = executor.run(WorkflowTestHelpers::SimpleInput.new(text: "hello"))

      expect(result.success).to be true
      join_output = result.step_results[:join].output.text
      expect(join_output).to include("left=hello:appended")
      expect(join_output).to include("right=HELLO")
    end
  end

  describe "error handling" do
    it "retries a failed step up to the global default retry count" do
      agent = counting_fail.new(fail_times: 2)

      workflow = PersonalAgentsTool::Workflow::Definition.define("retry") do |w|
        w.step :flaky, counting_fail
      end

      executor = PersonalAgentsTool::Workflow::Executor.new(
        workflow,
        retries: 2,
        agents: { flaky: agent }
      )

      allow(executor).to receive(:sleep)

      result = executor.run(WorkflowTestHelpers::SimpleInput.new(text: "try"))

      expect(result.success).to be true
      expect(agent.attempts).to eq(3)
    end

    it "respects per-agent retry count overrides" do
      agent = counting_fail.new(fail_times: 1)

      workflow = PersonalAgentsTool::Workflow::Definition.define("retry_override") do |w|
        w.step :flaky, counting_fail, retries: 1
      end

      executor = PersonalAgentsTool::Workflow::Executor.new(
        workflow,
        retries: 0,
        agents: { flaky: agent }
      )

      allow(executor).to receive(:sleep)

      result = executor.run(WorkflowTestHelpers::SimpleInput.new(text: "try"))

      expect(result.success).to be true
      expect(agent.attempts).to eq(2)
    end

    it "uses exponential backoff between retries" do
      sleep_durations = []
      agent = counting_fail.new(fail_times: 3)

      workflow = PersonalAgentsTool::Workflow::Definition.define("backoff") do |w|
        w.step :flaky, counting_fail
      end

      executor = PersonalAgentsTool::Workflow::Executor.new(
        workflow,
        retries: 3,
        agents: { flaky: agent }
      )

      allow(executor).to receive(:sleep) { |d| sleep_durations << d }

      result = executor.run(WorkflowTestHelpers::SimpleInput.new(text: "try"))

      expect(result.success).to be true
      expect(sleep_durations).to eq([1, 2, 4])
    end

    it "marks the step as failed after exhausting retries" do
      workflow = PersonalAgentsTool::Workflow::Definition.define("fail") do |w|
        w.step :bad, failing_agent
      end

      executor = PersonalAgentsTool::Workflow::Executor.new(workflow, retries: 1)
      allow(executor).to receive(:sleep)

      result = executor.run(WorkflowTestHelpers::SimpleInput.new(text: "test"))

      expect(result.success).to be false
      expect(result.failed_step).to eq(:bad)
    end

    it "does not run downstream steps when an upstream step fails" do
      workflow = PersonalAgentsTool::Workflow::Definition.define("fail_chain") do |w|
        w.step :bad, failing_agent
        w.step :after_bad, append_agent, after: :bad
      end

      executor = PersonalAgentsTool::Workflow::Executor.new(workflow)

      result = executor.run(WorkflowTestHelpers::SimpleInput.new(text: "test"))

      expect(result.success).to be false
      expect(result.step_results).not_to have_key(:after_bad)
    end

    it "reports which step failed and the error details" do
      workflow = PersonalAgentsTool::Workflow::Definition.define("fail_report") do |w|
        w.step :bad, failing_agent
      end

      executor = PersonalAgentsTool::Workflow::Executor.new(workflow)

      result = executor.run(WorkflowTestHelpers::SimpleInput.new(text: "test"))

      expect(result.success).to be false
      expect(result.failed_step).to eq(:bad)
      expect(result.error).to include("I always fail")
      expect(result.error_details).to be_a(String)
    end
  end

  describe "persistence integration" do
    let(:run_store) { PersonalAgentsTool::Persistence::RunStore.new(base_dir: "/tmp/test_runs") }
    let(:run_dir) { "/tmp/test_runs/persist_test_20260227" }

    before do
      allow(run_store).to receive(:create_run).and_return(run_dir)
      allow(run_store).to receive(:update_run_status)
      allow(run_store).to receive(:mark_step_in_progress)
      allow(run_store).to receive(:mark_step_completed)
      allow(run_store).to receive(:mark_step_failed)
    end

    it "creates a run and marks it in_progress on start" do
      workflow = PersonalAgentsTool::Workflow::Definition.define("persist_test") do |w|
        w.step :only, pass_through
      end

      executor = PersonalAgentsTool::Workflow::Executor.new(workflow, run_store: run_store)
      executor.run(WorkflowTestHelpers::SimpleInput.new(text: "hi"))

      expect(run_store).to have_received(:create_run).with(
        workflow_name: "persist_test",
        step_names: ["only"]
      )
      expect(run_store).to have_received(:update_run_status).with(
        run_dir: run_dir,
        status: "in_progress"
      )
    end

    it "marks each step in_progress and completed on success" do
      workflow = PersonalAgentsTool::Workflow::Definition.define("persist_test") do |w|
        w.step :a, pass_through
        w.step :b, append_agent, after: :a
      end

      executor = PersonalAgentsTool::Workflow::Executor.new(workflow, run_store: run_store)
      executor.run(WorkflowTestHelpers::SimpleInput.new(text: "hi"))

      expect(run_store).to have_received(:mark_step_in_progress).with(run_dir: run_dir, step_name: "a")
      expect(run_store).to have_received(:mark_step_in_progress).with(run_dir: run_dir, step_name: "b")
      expect(run_store).to have_received(:mark_step_completed).with(run_dir: run_dir, step_name: "a", duration: a_kind_of(Float))
      expect(run_store).to have_received(:mark_step_completed).with(run_dir: run_dir, step_name: "b", duration: a_kind_of(Float))
      expect(run_store).to have_received(:update_run_status).with(run_dir: run_dir, status: "completed")
    end

    it "marks the run as failed and persists step failure on error" do
      workflow = PersonalAgentsTool::Workflow::Definition.define("persist_fail") do |w|
        w.step :bad, failing_agent
      end

      executor = PersonalAgentsTool::Workflow::Executor.new(workflow, run_store: run_store)
      result = executor.run(WorkflowTestHelpers::SimpleInput.new(text: "hi"))

      expect(result.success).to be false
      expect(run_store).to have_received(:mark_step_in_progress).with(run_dir: run_dir, step_name: "bad")
      expect(run_store).to have_received(:mark_step_failed).with(run_dir: run_dir, step_name: "bad", error: an_instance_of(RuntimeError))
      expect(run_store).to have_received(:update_run_status).with(run_dir: run_dir, status: "failed")
    end

    it "does not call persistence methods when no run_store is provided" do
      workflow = PersonalAgentsTool::Workflow::Definition.define("no_persist") do |w|
        w.step :only, pass_through
      end

      executor = PersonalAgentsTool::Workflow::Executor.new(workflow)
      result = executor.run(WorkflowTestHelpers::SimpleInput.new(text: "hi"))

      expect(result.success).to be true
      expect(run_store).not_to have_received(:create_run)
    end
  end
end
