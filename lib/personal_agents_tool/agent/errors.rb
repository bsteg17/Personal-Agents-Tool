# frozen_string_literal: true
# typed: strict

module PersonalAgentsTool
  module Agent
    class Error < StandardError; end
    class InvalidInputError < Error; end
    class InvalidOutputError < Error; end
    class NotImplementedError < Error; end
  end
end
