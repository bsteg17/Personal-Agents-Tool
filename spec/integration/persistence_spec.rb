# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

module PersistenceTest
  class Input < T::Struct
    const :topic, String
  end

  class Output < T::Struct
    const :title, String
    const :body, String
  end
end

RSpec.describe "Persistence" do
  let(:base_dir) { Dir.mktmpdir }
  let(:store) { PersonalAgentsTool::Persistence::RunStore.new(base_dir: base_dir) }
  let(:step_names) { %w[draft edit format] }

  after { FileUtils.remove_entry(base_dir) }

  describe "run directory structure" do
    it "creates a run directory named with workflow name and timestamp" do
      run_dir = store.create_run(workflow_name: "content_pipeline", step_names: step_names)
      dir_name = File.basename(run_dir)

      expect(dir_name).to match(/\Acontent_pipeline_\d{8}_\d{6}\z/)
      expect(Dir.exist?(run_dir)).to be true
    end

    it "writes a metadata.json with workflow config, status, and timestamps" do
      run_dir = store.create_run(
        workflow_name: "content_pipeline",
        step_names: step_names,
        config: { "model" => "claude-3" }
      )

      metadata = store.read_metadata(run_dir: run_dir)

      expect(metadata.workflow_name).to eq("content_pipeline")
      expect(metadata.status).to eq("pending")
      expect(metadata.steps).to eq(step_names)
      expect(metadata.config).to eq({ "model" => "claude-3" })
      expect(metadata.created_at).not_to be_nil
      expect(metadata.updated_at).not_to be_nil
    end

    it "creates a steps subdirectory for each step" do
      run_dir = store.create_run(workflow_name: "content_pipeline", step_names: step_names)

      step_names.each do |step_name|
        step_dir = File.join(run_dir, "steps", step_name)
        expect(Dir.exist?(step_dir)).to be true
      end
    end

    it "writes input.json for each step before execution" do
      run_dir = store.create_run(workflow_name: "content_pipeline", step_names: step_names)
      step = store.step_store(run_dir: run_dir, step_name: "draft")

      input = PersistenceTest::Input.new(topic: "Ruby agents")
      step.write_input(input)

      loaded = step.read_input(PersistenceTest::Input)
      expect(loaded.topic).to eq("Ruby agents")
    end

    it "writes output.json for each step after successful execution" do
      run_dir = store.create_run(workflow_name: "content_pipeline", step_names: step_names)
      step = store.step_store(run_dir: run_dir, step_name: "draft")

      output = PersistenceTest::Output.new(title: "Agent Guide", body: "How to build agents")
      step.write_output(output)

      loaded = step.read_output(PersistenceTest::Output)
      expect(loaded.title).to eq("Agent Guide")
      expect(loaded.body).to eq("How to build agents")
    end

    it "writes status.json tracking completed/failed/pending and retry count" do
      run_dir = store.create_run(workflow_name: "content_pipeline", step_names: step_names)

      statuses = store.load_step_statuses(run_dir: run_dir)

      step_names.each do |step_name|
        expect(statuses[step_name].status).to eq("pending")
        expect(statuses[step_name].retry_count).to eq(0)
      end

      store.mark_step_in_progress(run_dir: run_dir, step_name: "draft")
      store.mark_step_completed(run_dir: run_dir, step_name: "draft", duration: 1.5)

      updated = store.load_step_statuses(run_dir: run_dir)
      expect(updated["draft"].status).to eq("completed")
      expect(updated["edit"].status).to eq("pending")
    end
  end

  describe "resumability" do
    let(:run_dir) do
      store.create_run(workflow_name: "content_pipeline", step_names: step_names)
    end

    before do
      # Simulate: draft completed, edit was in_progress (crash), format pending
      step = store.step_store(run_dir: run_dir, step_name: "draft")
      step.write_input(PersistenceTest::Input.new(topic: "Ruby agents"))
      step.write_output(PersistenceTest::Output.new(title: "Draft Title", body: "Draft body"))
      store.mark_step_in_progress(run_dir: run_dir, step_name: "draft")
      store.mark_step_completed(run_dir: run_dir, step_name: "draft", duration: 2.0)

      store.mark_step_in_progress(run_dir: run_dir, step_name: "edit")
    end

    it "resumes a crashed workflow from the last incomplete step" do
      plan = store.resume_plan(run_dir: run_dir)

      expect(plan[:resume_step]).to eq("edit")
    end

    it "loads persisted outputs for already-completed steps" do
      output = store.load_step_output(
        run_dir: run_dir,
        step_name: "draft",
        struct_class: PersistenceTest::Output
      )

      expect(output).to be_a(PersistenceTest::Output)
      expect(T.cast(output, PersistenceTest::Output).title).to eq("Draft Title")
    end

    it "does not re-run steps that completed successfully" do
      plan = store.resume_plan(run_dir: run_dir)

      expect(plan[:completed]).to eq(["draft"])
      expect(plan[:completed]).not_to include("edit")
      expect(plan[:completed]).not_to include("format")
    end

    it "re-runs the step that was in progress when the crash occurred" do
      plan = store.resume_plan(run_dir: run_dir)

      expect(plan[:resume_step]).to eq("edit")
      status = store.load_step_statuses(run_dir: run_dir)
      expect(status["edit"].status).to eq("in_progress")
    end

    it "continues running downstream steps after resuming" do
      plan = store.resume_plan(run_dir: run_dir)

      expect(plan[:pending]).to eq(["format"])
    end
  end

  describe "inspectability" do
    it "serializes step outputs as human-readable JSON" do
      run_dir = store.create_run(workflow_name: "content_pipeline", step_names: step_names)
      step = store.step_store(run_dir: run_dir, step_name: "draft")

      output = PersistenceTest::Output.new(title: "Agent Guide", body: "How to build agents")
      step.write_output(output)

      raw_json = File.read(File.join(run_dir, "steps", "draft", "output.json"))
      expect(raw_json).to include("\n")
      expect(raw_json).to include("  ")

      parsed = JSON.parse(raw_json)
      expect(parsed["title"]).to eq("Agent Guide")
    end

    it "records errors and retry attempts in status.json" do
      run_dir = store.create_run(workflow_name: "content_pipeline", step_names: step_names)

      store.mark_step_in_progress(run_dir: run_dir, step_name: "draft")
      store.mark_step_failed(
        run_dir: run_dir,
        step_name: "draft",
        error: RuntimeError.new("API timeout")
      )

      status = store.load_step_statuses(run_dir: run_dir)["draft"]

      expect(status.status).to eq("failed")
      expect(status.retry_count).to eq(1)
      expect(status.error).to eq("API timeout")
      expect(status.error_class).to eq("RuntimeError")
      expect(status.retries.length).to eq(1)
      expect(status.retries[0]["error"]).to eq("API timeout")
      expect(status.retries[0]["error_class"]).to eq("RuntimeError")
      expect(status.retries[0]["timestamp"]).not_to be_nil
    end

    it "records wall-clock duration per step" do
      run_dir = store.create_run(workflow_name: "content_pipeline", step_names: step_names)

      store.mark_step_in_progress(run_dir: run_dir, step_name: "draft")
      store.mark_step_completed(run_dir: run_dir, step_name: "draft", duration: 3.14)

      status = store.load_step_statuses(run_dir: run_dir)["draft"]

      expect(status.status).to eq("completed")
      expect(status.duration).to eq(3.14)
      expect(status.completed_at).not_to be_nil
    end
  end
end
