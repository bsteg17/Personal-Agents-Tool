# frozen_string_literal: true
# typed: strict

require "json"
require "fileutils"
require "time"
require "sorbet-runtime"

module PersonalAgentsTool
  module Persistence
    class RunStore
      extend T::Sig

      sig { params(base_dir: String).void }
      def initialize(base_dir: "./runs")
        @base_dir = T.let(base_dir, String)
      end

      sig { returns(String) }
      attr_reader :base_dir

      sig do
        params(
          workflow_name: String,
          step_names: T::Array[String],
          config: T::Hash[String, T.untyped]
        ).returns(String)
      end
      def create_run(workflow_name:, step_names:, config: {})
        timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
        run_dir = File.join(@base_dir, "#{workflow_name}_#{timestamp}")

        FileUtils.mkdir_p(run_dir)

        now = Time.now.iso8601
        metadata = RunMetadata.new(
          workflow_name: workflow_name,
          status: "pending",
          steps: step_names,
          created_at: now,
          updated_at: now,
          config: config
        )
        File.write(File.join(run_dir, "metadata.json"), Serializer.to_json(metadata))

        steps_dir = File.join(run_dir, "steps")
        FileUtils.mkdir_p(steps_dir)

        step_names.each do |step_name|
          step_dir = File.join(steps_dir, step_name)
          FileUtils.mkdir_p(step_dir)

          pending_status = StepStatus.new(status: "pending")
          store = StepStore.new(step_dir)
          store.write_status(pending_status)
        end

        run_dir
      end

      sig { params(run_dir: String, step_name: String).returns(StepStore) }
      def step_store(run_dir:, step_name:)
        step_dir = File.join(run_dir, "steps", step_name)
        raise RunNotFoundError, "Step directory not found: #{step_dir}" unless Dir.exist?(step_dir)

        StepStore.new(step_dir)
      end

      sig { params(run_dir: String, step_name: String).void }
      def mark_step_in_progress(run_dir:, step_name:)
        store = step_store(run_dir: run_dir, step_name: step_name)
        current = store.read_status

        updated = StepStatus.new(
          status: "in_progress",
          retry_count: current.retry_count,
          started_at: Time.now.iso8601,
          retries: current.retries
        )
        store.write_status(updated)
      end

      sig { params(run_dir: String, step_name: String, duration: Float).void }
      def mark_step_completed(run_dir:, step_name:, duration:)
        store = step_store(run_dir: run_dir, step_name: step_name)
        current = store.read_status

        updated = StepStatus.new(
          status: "completed",
          retry_count: current.retry_count,
          started_at: current.started_at,
          completed_at: Time.now.iso8601,
          duration: duration,
          retries: current.retries
        )
        store.write_status(updated)
      end

      sig { params(run_dir: String, step_name: String, error: StandardError).void }
      def mark_step_failed(run_dir:, step_name:, error:)
        store = step_store(run_dir: run_dir, step_name: step_name)
        current = store.read_status

        retry_entry = {
          "error" => error.message,
          "error_class" => error.class.name,
          "timestamp" => Time.now.iso8601
        }

        updated = StepStatus.new(
          status: "failed",
          retry_count: current.retry_count + 1,
          error: error.message,
          error_class: error.class.name,
          started_at: current.started_at,
          retries: current.retries + [retry_entry]
        )
        store.write_status(updated)
      end

      sig { params(run_dir: String, status: String).void }
      def update_run_status(run_dir:, status:)
        metadata = read_metadata(run_dir: run_dir)

        updated = RunMetadata.new(
          workflow_name: metadata.workflow_name,
          status: status,
          steps: metadata.steps,
          created_at: metadata.created_at,
          updated_at: Time.now.iso8601,
          config: metadata.config
        )
        File.write(File.join(run_dir, "metadata.json"), Serializer.to_json(updated))
      end

      sig { params(run_dir: String).returns(RunMetadata) }
      def read_metadata(run_dir:)
        path = File.join(run_dir, "metadata.json")
        raise RunNotFoundError, "Metadata not found: #{path}" unless File.exist?(path)

        T.cast(Serializer.from_json(File.read(path), RunMetadata), RunMetadata)
      end

      sig { params(run_dir: String).returns(T::Hash[String, StepStatus]) }
      def load_step_statuses(run_dir:)
        metadata = read_metadata(run_dir: run_dir)
        result = T.let({}, T::Hash[String, StepStatus])

        metadata.steps.each do |step_name|
          store = step_store(run_dir: run_dir, step_name: step_name)
          result[step_name] = store.read_status
        end

        result
      end

      sig do
        params(run_dir: String).returns(
          T::Hash[Symbol, T.any(T::Array[String], T.nilable(String))]
        )
      end
      def resume_plan(run_dir:)
        statuses = load_step_statuses(run_dir: run_dir)
        metadata = read_metadata(run_dir: run_dir)

        completed = T.let([], T::Array[String])
        resume_step = T.let(nil, T.nilable(String))
        pending = T.let([], T::Array[String])

        metadata.steps.each do |step_name|
          status = T.must(statuses[step_name])
          case status.status
          when "completed"
            completed << step_name
          when "in_progress", "failed"
            if resume_step.nil?
              resume_step = step_name
            else
              pending << step_name
            end
          when "pending"
            pending << step_name
          end
        end

        {
          completed: completed,
          resume_step: resume_step,
          pending: pending
        }
      end

      sig do
        params(
          run_dir: String,
          step_name: String,
          struct_class: T.class_of(T::Struct)
        ).returns(T::Struct)
      end
      def load_step_output(run_dir:, step_name:, struct_class:)
        store = step_store(run_dir: run_dir, step_name: step_name)
        store.read_output(struct_class)
      end
    end
  end
end
