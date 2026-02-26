# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Content Pipeline (first workflow)" do
  describe "end to end" do
    it "runs the full content pipeline from topic to formatted output"
    it "persists all intermediate results to the run directory"
    it "can be resumed if interrupted mid-pipeline"
  end

  describe "DraftWriter agent" do
    it "accepts a topic input and produces a draft output via LLM"
    it "includes the topic in the LLM prompt"
    it "returns structured output with title and body fields"
  end

  describe "Editor agent" do
    it "accepts draft output and produces an edited version via LLM"
    it "preserves the original structure while improving clarity"
  end

  describe "ImageGenerator agent" do
    it "accepts draft output and produces image descriptions or URLs"
    it "calls an external image generation API"
    it "runs in parallel with the Editor step"
  end

  describe "Formatter agent" do
    it "accepts edited text and images as input"
    it "assembles final output combining text and images"
    it "runs as pure code without an LLM call"
  end
end
