# frozen_string_literal: true
# typed: strict

require "sorbet-runtime"

module PersonalAgentsTool
  module LLM
    class ToolCall < T::Struct
      const :name, Symbol
      const :arguments, T.untyped
    end
  end
end
