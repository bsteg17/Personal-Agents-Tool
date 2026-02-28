# frozen_string_literal: true
# typed: strict

module PersonalAgentsTool
  module Persistence
    class Error < StandardError; end
    class RunNotFoundError < Error; end
    class CorruptedRunError < Error; end
  end
end
