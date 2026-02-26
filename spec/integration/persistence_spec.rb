# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Persistence" do
  describe "run directory structure" do
    it "creates a run directory named with workflow name and timestamp"
    it "writes a metadata.json with workflow config, status, and timestamps"
    it "creates a steps subdirectory for each step"
    it "writes input.json for each step before execution"
    it "writes output.json for each step after successful execution"
    it "writes status.json tracking completed/failed/pending and retry count"
  end

  describe "resumability" do
    it "resumes a crashed workflow from the last incomplete step"
    it "loads persisted outputs for already-completed steps"
    it "does not re-run steps that completed successfully"
    it "re-runs the step that was in progress when the crash occurred"
    it "continues running downstream steps after resuming"
  end

  describe "inspectability" do
    it "serializes step outputs as human-readable JSON"
    it "records errors and retry attempts in status.json"
    it "records wall-clock duration per step"
  end
end
