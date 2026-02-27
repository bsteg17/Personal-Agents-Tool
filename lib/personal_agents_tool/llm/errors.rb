# frozen_string_literal: true
# typed: strict

module PersonalAgentsTool
  module LLM
    class Error < StandardError; end
    class ParseError < Error; end
    class UnknownProviderError < Error; end
  end
end
