# frozen_string_literal: true
# typed: strict

require "sorbet-runtime"

module PersonalAgentsTool
  module Workflow
    class Executor
      extend T::Sig

      sig do
        params(
          definition: Definition,
          retries: Integer,
          agents: T::Hash[Symbol, Agent::Base],
          run_store: T.nilable(Persistence::RunStore)
        ).void
      end
      def initialize(definition, retries: 0, agents: {}, run_store: nil)
        @definition = T.let(definition, Definition)
        @global_retries = T.let(retries, Integer)
        @agents = T.let(agents, T::Hash[Symbol, Agent::Base])
        @run_store = T.let(run_store, T.nilable(Persistence::RunStore))
      end

      sig { params(initial_input: T::Struct).returns(Result) }
      def run(initial_input)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        step_results = T.let({}, T::Hash[Symbol, Agent::Result])
        failed_step = T.let(nil, T.nilable(Symbol))
        error_message = T.let(nil, T.nilable(String))
        error_details = T.let(nil, T.nilable(String))

        # Initialize persistence run if run_store provided
        run_dir = T.let(nil, T.nilable(String))
        if @run_store
          step_names = @definition.steps.keys.map(&:to_s)
          run_dir = @run_store.create_run(
            workflow_name: @definition.name,
            step_names: step_names
          )
          @run_store.update_run_status(run_dir: run_dir, status: "in_progress")
        end

        # Build dependency tracking
        steps = @definition.steps
        remaining = steps.keys.to_set
        completed = Set.new

        while remaining.any? && failed_step.nil?
          # Find ready steps: all deps completed
          ready = remaining.select do |name|
            step_def = steps.fetch(name)
            step_def.after.all? { |dep| completed.include?(dep) }
          end

          break if ready.empty?

          # Launch ready steps in parallel
          queue = Queue.new
          threads = ready.map do |name|
            Thread.new do
              step_def = steps.fetch(name)
              persist_step_in_progress(run_dir, name)
              result = execute_step_with_retries(step_def, initial_input, step_results)
              persist_step_completed(run_dir, name, T.must(result.duration))
              queue.push([name, result, nil])
            rescue StandardError => e
              persist_step_failed(run_dir, name, e)
              queue.push([name, nil, e])
            end
          end

          # Collect results
          ready.size.times do
            name, result, err = queue.pop
            name = T.cast(name, Symbol)

            if err
              err = T.cast(err, StandardError)
              failed_step = name
              error_message = "Step :#{name} failed: #{err.message}"
              error_details = err.backtrace&.first(5)&.join("\n")
              break
            else
              result = T.cast(result, Agent::Result)
              step_results[name] = result
              completed.add(name)
              remaining.delete(name)
            end
          end

          # Make sure all threads finish
          threads.each(&:join)
        end

        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

        if @run_store && run_dir
          final_status = failed_step.nil? ? "completed" : "failed"
          @run_store.update_run_status(run_dir: run_dir, status: final_status)
        end

        Result.new(
          success: failed_step.nil?,
          step_results: step_results,
          failed_step: failed_step,
          error: error_message,
          error_details: error_details,
          duration: duration
        )
      end

      private

      sig do
        params(
          step_def: StepDefinition,
          initial_input: T::Struct,
          step_results: T::Hash[Symbol, Agent::Result]
        ).returns(Agent::Result)
      end
      def execute_step_with_retries(step_def, initial_input, step_results)
        max_retries = step_def.retries || @global_retries
        agent = @agents[step_def.name] || step_def.agent_class.new
        input = build_input(step_def, initial_input, step_results)

        attempt = 0
        loop do
          begin
            return agent.execute(input)
          rescue StandardError => e
            attempt += 1
            raise e if attempt > max_retries

            backoff = 2**(attempt - 1)
            sleep(backoff)
          end
        end
      end

      sig { params(run_dir: T.nilable(String), step_name: Symbol).void }
      def persist_step_in_progress(run_dir, step_name)
        return unless @run_store && run_dir

        @run_store.mark_step_in_progress(run_dir: run_dir, step_name: step_name.to_s)
      end

      sig { params(run_dir: T.nilable(String), step_name: Symbol, duration: Float).void }
      def persist_step_completed(run_dir, step_name, duration)
        return unless @run_store && run_dir

        @run_store.mark_step_completed(run_dir: run_dir, step_name: step_name.to_s, duration: duration)
      end

      sig { params(run_dir: T.nilable(String), step_name: Symbol, error: StandardError).void }
      def persist_step_failed(run_dir, step_name, error)
        return unless @run_store && run_dir

        @run_store.mark_step_failed(run_dir: run_dir, step_name: step_name.to_s, error: error)
      end

      sig do
        params(
          step_def: StepDefinition,
          initial_input: T::Struct,
          step_results: T::Hash[Symbol, Agent::Result]
        ).returns(T::Struct)
      end
      def build_input(step_def, initial_input, step_results)
        deps = step_def.after

        if deps.empty?
          initial_input
        elsif deps.size == 1
          T.must(step_results[T.must(deps.first)]).output
        else
          outputs = T.let({}, T::Hash[Symbol, T::Struct])
          deps.each do |dep|
            outputs[dep] = T.must(step_results[dep]).output
          end
          MergedInput.new(outputs: outputs)
        end
      end
    end
  end
end
