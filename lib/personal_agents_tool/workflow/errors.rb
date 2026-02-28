# frozen_string_literal: true
# typed: strict

module PersonalAgentsTool
  module Workflow
    class Error < StandardError; end
    class CircularDependencyError < Error; end
    class MissingDependencyError < Error; end
    class StepFailedError < Error; end
  end
end
